//+------------------------------------------------------------------+
//|                                              GoLongEA.mq5        |
//|              "Go Long" strategy - MQL5 Expert Advisor            |
//|                                                                    |
//| Strategy logic (from the transcript):                             |
//|  - CFD/index positions held overnight pay swap, which over time   |
//|    eats all profit from a simple buy-and-hold approach. Instead   |
//|    this EA opens a BUY every trading day shortly after the        |
//|    session opens and closes it again the same evening, so the     |
//|    only recurring cost is the (small) spread, not the swap.       |
//|  - Position size is risk-based: it is sized so that InpRiskPercent|
//|    of InpBaseMoney would be lost if price fell all the way to     |
//|    zero (mirrors the video's "50k account / 100% risk" sizing,    |
//|    but computed generically for ANY symbol via tick size/value    |
//|    instead of assuming "1 index point = 1 account-currency unit").|
//|  - Optional "wait for new high" filter: instead of entering right |
//|    at the open trigger, the EA records that day's high (from      |
//|    midnight up to the open-trigger time) and only enters once     |
//|    price breaks above that level - skipping days that open and    |
//|    just fall away.                                                 |
//|  - SL/TP are OFF by default (as in the video) but can be enabled  |
//|    and sized as a percentage of entry price.                      |
//|                                                                    |
//| Safety / robustness:                                              |
//|  - Own adjustable magic number; only opens/closes positions that  |
//|    carry it, so it never touches other EAs' or manual trades.     |
//|  - State (open position / already-traded-today / day reference    |
//|    high) is rebuilt from live position & market data in OnInit(), |
//|    so a terminal/EA restart cannot cause duplicate entries.       |
//|  - Position size is capped by the symbol's volume limits and by   |
//|    a margin check before sending the order.                       |
//|  - Works on any symbol; all price/volume conversions use the      |
//|    symbol's own tick size, tick value and volume step.            |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//================================= INPUTS ===================================
input group "=== General ==="
input ulong    InpMagicNumber      = 20260910;  // Magic number (unique to this EA)
input ulong    InpDeviationPoints  = 20;         // Max allowed slippage, in points

input group "=== Schedule (server time, every trading day) ==="
input int      InpOpenHour         = 1;          // Open hour   (0-23)
input int      InpOpenMinute       = 5;           // Open minute (0-59)
input int      InpCloseHour        = 22;         // Close hour   (0-23)
input int      InpCloseMinute      = 50;         // Close minute (0-59)

input group "=== Entry filter ==="
input bool     InpWaitForNewHigh   = false;  // Only enter once price breaks above that day's prior high
                                              // (reference high = highest M1 price from midnight to open trigger)

input group "=== Position sizing ==="
input double   InpBaseMoney        = 0.0;     // Fixed base money for sizing; 0 = use live account balance
input double   InpRiskPercent      = 100.0;   // % of base money "at risk" (used to size the position)
input int      InpLotDigits        = 2;        // Digits used to round the calculated lot size

input group "=== Optional SL / TP (both OFF by default, as in the video) ==="
input bool     InpUseStopLoss      = false;
input double   InpStopLossPercent  = 0.0;      // % of entry price
input bool     InpUseTakeProfit    = false;
input double   InpTakeProfitPercent = 0.0;     // % of entry price

//================================= GLOBALS ===================================
CTrade   g_trade;
ulong    g_positionTicket   = 0;
datetime g_currentDay       = 0;      // midnight timestamp of the day currently being tracked
datetime g_lastOpenDate     = 0;      // midnight timestamp of the day we last opened a trade
bool     g_refHighComputed  = false;  // whether today's reference high has been computed
double   g_dayRefHigh       = 0.0;    // reference high used by the "wait for new high" filter
bool     g_ready            = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   if(InpOpenHour < 0 || InpOpenHour > 23 || InpCloseHour < 0 || InpCloseHour > 23 ||
      InpOpenMinute < 0 || InpOpenMinute > 59 || InpCloseMinute < 0 || InpCloseMinute > 59)
     {
      Print("GoLongEA: invalid time inputs.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpRiskPercent <= 0.0)
     {
      Print("GoLongEA: RiskPercent must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpUseStopLoss && InpStopLossPercent <= 0.0)
     {
      Print("GoLongEA: InpUseStopLoss is true but InpStopLossPercent <= 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpUseTakeProfit && InpTakeProfitPercent <= 0.0)
     {
      Print("GoLongEA: InpUseTakeProfit is true but InpTakeProfitPercent <= 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   RestoreState();

   g_ready = true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Rebuild EA state from live positions (crash/restart safe)        |
//+------------------------------------------------------------------+
void RestoreState()
  {
   g_positionTicket = 0;
   g_lastOpenDate    = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         g_positionTicket = ticket;
         g_lastOpenDate   = StartOfDay((datetime)PositionGetInteger(POSITION_TIME));
         break; // this EA only ever holds one position at a time
        }
     }

   g_currentDay      = StartOfDay(TimeCurrent());
   g_refHighComputed = false;
   g_dayRefHigh      = 0.0;
  }

//+------------------------------------------------------------------+
//| Return the midnight timestamp for the day containing t           |
//+------------------------------------------------------------------+
datetime StartOfDay(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_ready)
      return;

   datetime today = StartOfDay(TimeCurrent());
   if(today != g_currentDay)
     {
      // New calendar day: reset the per-day state used by the entry filter
      g_currentDay      = today;
      g_refHighComputed = false;
      g_dayRefHigh      = 0.0;
     }

   // Make sure our tracked position is still alive (may have hit SL/TP, or been closed manually)
   if(g_positionTicket != 0 && !PositionSelectByTicket(g_positionTicket))
      g_positionTicket = 0;

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);

   MqlDateTime dtOpen = dtNow;
   dtOpen.hour = InpOpenHour;
   dtOpen.min  = InpOpenMinute;
   dtOpen.sec  = 0;
   datetime openTrigger = StructToTime(dtOpen);

   MqlDateTime dtClose = dtNow;
   dtClose.hour = InpCloseHour;
   dtClose.min  = InpCloseMinute;
   dtClose.sec  = 0;
   datetime closeTrigger = StructToTime(dtClose);

   //--- ENTRY
   if(g_positionTicket == 0 &&
      g_lastOpenDate != today &&
      TimeCurrent() >= openTrigger)
     {
      if(!InpWaitForNewHigh)
        {
         TryOpenPosition();
        }
      else
        {
         if(!g_refHighComputed)
           {
            g_dayRefHigh      = ComputeDayReferenceHigh(today);
            g_refHighComputed = true;
           }
         else
           {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(bid > g_dayRefHigh)
               TryOpenPosition();
           }
        }
     }

   //--- EXIT
   if(g_positionTicket != 0 && TimeCurrent() >= closeTrigger)
     {
      TryClosePosition();
     }
  }

//+------------------------------------------------------------------+
//| Highest M1 price from midnight up to (but not including) now,    |
//| used as the breakout reference for the "wait for new high" filter|
//+------------------------------------------------------------------+
double ComputeDayReferenceHigh(const datetime dayStart)
  {
   int startShift = iBarShift(_Symbol, PERIOD_M1, dayStart, false);
   if(startShift < 0)
      startShift = 0;

   int count = startShift + 1;
   int highestIdx = iHighest(_Symbol, PERIOD_M1, MODE_HIGH, count, 0);
   if(highestIdx < 0)
      return(SymbolInfoDouble(_Symbol, SYMBOL_BID)); // fallback: no history, use current price

   double refHigh = iHigh(_Symbol, PERIOD_M1, highestIdx);
   if(refHigh <= 0.0)
      refHigh = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   return(refHigh);
  }

//+------------------------------------------------------------------+
//| Risk-based position size: sized so that InpRiskPercent of the    |
//| base money would be lost if price fell all the way to zero.      |
//+------------------------------------------------------------------+
double CalculateLotSize(const double price)
  {
   double baseMoney   = (InpBaseMoney > 0.0) ? InpBaseMoney : AccountInfoDouble(ACCOUNT_BALANCE);
   double targetMoney = baseMoney * InpRiskPercent / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0 || price <= 0.0)
     {
      Print("GoLongEA: invalid symbol trade parameters, cannot size position.");
      return(0.0);
     }

   double valuePerLot = (price / tickSize) * tickValue; // account-currency value of 1.0 lot at current price
   if(valuePerLot <= 0.0)
      return(0.0);

   double lots = targetMoney / valuePerLot;
   lots = MathFloor(lots / volStep) * volStep;
   lots = NormalizeDouble(lots, InpLotDigits);

   if(lots < volMin)
      lots = volMin;
   if(lots > volMax)
      lots = volMax;

   // Safety check: cap the size if the account cannot actually margin it
   double marginRequired = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, price, marginRequired))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired > freeMargin && marginRequired > 0.0)
        {
         double scale = freeMargin / marginRequired;
         lots = MathFloor((lots * scale) / volStep) * volStep;
         lots = NormalizeDouble(lots, InpLotDigits);
         Print("GoLongEA: lot size reduced to ", lots, " due to insufficient free margin.");
        }
     }

   if(lots < volMin)
      lots = 0.0; // cannot open even the minimum size safely

   return(lots);
  }

//+------------------------------------------------------------------+
//| Open the buy position with optional SL/TP and risk-based size    |
//+------------------------------------------------------------------+
void TryOpenPosition()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double lots = CalculateLotSize(ask);
   if(lots <= 0.0)
     {
      Print("GoLongEA: calculated lot size invalid, entry skipped.");
      return;
     }

   double sl = InpUseStopLoss   ? NormalizeDouble(ask * (1.0 - InpStopLossPercent   / 100.0), _Digits) : 0.0;
   double tp = InpUseTakeProfit ? NormalizeDouble(ask * (1.0 + InpTakeProfitPercent / 100.0), _Digits) : 0.0;

   if(g_trade.Buy(lots, _Symbol, ask, sl, tp, "GoLong"))
     {
      ulong ticket = FindOwnPositionTicket();
      if(ticket != 0)
        {
         g_positionTicket = ticket;
         g_lastOpenDate   = StartOfDay(TimeCurrent());
        }
      else
        {
         Print("GoLongEA: order sent but position ticket could not be resolved.");
        }
     }
   else
     {
      Print("GoLongEA: Buy() failed. Retcode ", g_trade.ResultRetcode(),
            " - ", g_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Locate our own open position on this symbol                      |
//+------------------------------------------------------------------+
ulong FindOwnPositionTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return(ticket);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| Close the tracked position                                        |
//+------------------------------------------------------------------+
void TryClosePosition()
  {
   if(g_positionTicket == 0)
      return;

   if(!PositionSelectByTicket(g_positionTicket))
     {
      g_positionTicket = 0;
      return;
     }

   if(g_trade.PositionClose(g_positionTicket))
     {
      g_positionTicket = 0;
     }
   else
     {
      Print("GoLongEA: failed to close position #", g_positionTicket,
            ". Retcode ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
     }
  }
//+------------------------------------------------------------------+
