//+------------------------------------------------------------------+
//|                                       TurnaroundTuesdayEA.mq5    |
//|         Turnaround Tuesday strategy - MQL5 Expert Advisor        |
//|                                                                    |
//| Strategy logic:                                                   |
//|  - On a configurable "open day" (default Monday) at a configurable|
//|    server time, if price (Bid) is below a configurable Moving     |
//|    Average filter, open ONE buy position with a risk-based lot    |
//|    size and a percentage stop loss.                               |
//|  - On a configurable "close day" (default Tuesday) at a           |
//|    configurable server time, close that position.                 |
//|  - Only one position at a time, tagged with its own magic number, |
//|    so it never touches trades belonging to other EAs/manual trades|
//|  - State (open position / already-traded-today) is rebuilt from   |
//|    live position data on every OnInit(), so a terminal/EA restart |
//|    does not cause duplicate entries or an orphaned position.      |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//================================= INPUTS ===================================
input group "=== General ==="
input ulong             InpMagicNumber     = 20260909;   // Magic number (unique to this EA)
input ulong             InpDeviationPoints = 20;         // Max allowed slippage, in points
input ENUM_TIMEFRAMES   InpBarTimeframe    = PERIOD_M1;  // Timeframe used to detect "new bar" heartbeat

input group "=== Entry / Exit schedule (server time) ==="
input ENUM_DAY_OF_WEEK  InpDayOpen         = MONDAY;     // Day of week to open the trade
input int                InpOpenHour        = 22;         // Open hour   (0-23)
input int                InpOpenMinute      = 55;         // Open minute (0-59)
input ENUM_DAY_OF_WEEK  InpDayClose        = TUESDAY;    // Day of week to close the trade
input int                InpCloseHour       = 22;         // Close hour   (0-23)
input int                InpCloseMinute     = 55;         // Close minute (0-59)

input group "=== Moving Average filter ==="
input bool               InpUseMAFilter     = true;        // Use MA filter (only buy when price < MA)
input ENUM_TIMEFRAMES   InpMATimeframe     = PERIOD_D1;    // MA timeframe
input int                InpMAPeriod        = 24;           // MA period
input ENUM_MA_METHOD    InpMAMethod        = MODE_SMA;     // MA method
input ENUM_APPLIED_PRICE InpMAAppliedPrice = PRICE_CLOSE;  // MA applied price

input group "=== Risk management ==="
input double             InpRiskPercent     = 1.0;   // Risk per trade, % of account balance
input double             InpStopLossPercent = 5.0;   // Stop loss distance, % of entry price
input int                InpLotDigits       = 2;      // Digits used to round the calculated lot size

//================================= GLOBALS ===================================
CTrade   g_trade;
int      g_handleMA      = INVALID_HANDLE;
datetime g_lastBarTime   = 0;
ulong    g_positionTicket = 0;
datetime g_lastOpenDate  = 0;     // midnight timestamp of the day we last opened a trade
bool     g_ready         = false;

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
      Print("TurnaroundTuesdayEA: invalid time inputs.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpRiskPercent <= 0.0 || InpStopLossPercent <= 0.0)
     {
      Print("TurnaroundTuesdayEA: RiskPercent and StopLossPercent must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpUseMAFilter)
     {
      g_handleMA = iMA(_Symbol, InpMATimeframe, InpMAPeriod, 0, InpMAMethod, InpMAAppliedPrice);
      if(g_handleMA == INVALID_HANDLE)
        {
         Print("TurnaroundTuesdayEA: failed to create MA handle. Error ", GetLastError());
         return(INIT_FAILED);
        }
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
   if(g_handleMA != INVALID_HANDLE)
      IndicatorRelease(g_handleMA);
  }

//+------------------------------------------------------------------+
//| Rebuild EA state from live positions (crash/restart safe)        |
//+------------------------------------------------------------------+
void RestoreState()
  {
   g_positionTicket = 0;
   g_lastOpenDate   = 0;

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

   // --- Only evaluate logic once per bar of InpBarTimeframe (avoids reprocessing every tick)
   datetime curBarTime = iTime(_Symbol, InpBarTimeframe, 0);
   if(curBarTime == 0 || curBarTime == g_lastBarTime)
      return;
   g_lastBarTime = curBarTime;

   // --- Make sure our tracked position is still alive (may have hit SL, or been closed manually)
   if(g_positionTicket != 0 && !PositionSelectByTicket(g_positionTicket))
      g_positionTicket = 0;

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   ENUM_DAY_OF_WEEK curDow = (ENUM_DAY_OF_WEEK)dtNow.day_of_week;

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

   datetime today = StartOfDay(TimeCurrent());

   //--- ENTRY
   if(g_positionTicket == 0 &&
      curDow == InpDayOpen &&
      TimeCurrent() >= openTrigger &&
      g_lastOpenDate != today)
     {
      if(PassesMAFilter())
         TryOpenPosition();
     }

   //--- EXIT
   if(g_positionTicket != 0 &&
      curDow == InpDayClose &&
      TimeCurrent() >= closeTrigger)
     {
      TryClosePosition();
     }
  }

//+------------------------------------------------------------------+
//| MA filter: true if entry is allowed (Bid below the MA)           |
//+------------------------------------------------------------------+
bool PassesMAFilter()
  {
   if(!InpUseMAFilter)
      return(true);

   double maBuf[];
   ArraySetAsSeries(maBuf, true);
   if(CopyBuffer(g_handleMA, 0, 0, 1, maBuf) <= 0)
     {
      Print("TurnaroundTuesdayEA: CopyBuffer(MA) failed. Error ", GetLastError());
      return(false);
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return(bid < maBuf[0]);
  }

//+------------------------------------------------------------------+
//| Risk-based position size, from SL distance in price               |
//+------------------------------------------------------------------+
double CalculateLotSize(const double entryPrice, const double slPrice)
  {
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0)
     {
      Print("TurnaroundTuesdayEA: invalid symbol trade parameters, cannot size position.");
      return(0.0);
     }

   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0.0)
      return(0.0);

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / volStep) * volStep;
   lots = NormalizeDouble(lots, InpLotDigits);

   if(lots < volMin)
      lots = volMin;
   if(lots > volMax)
      lots = volMax;

   return(lots);
  }

//+------------------------------------------------------------------+
//| Open the buy position with SL and risk-based size                |
//+------------------------------------------------------------------+
void TryOpenPosition()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = NormalizeDouble(ask * (1.0 - InpStopLossPercent / 100.0), _Digits);

   double lots = CalculateLotSize(ask, sl);
   if(lots <= 0.0)
     {
      Print("TurnaroundTuesdayEA: calculated lot size invalid, entry skipped.");
      return;
     }

   if(g_trade.Buy(lots, _Symbol, ask, sl, 0.0, "TurnaroundTuesday"))
     {
      ulong ticket = FindOwnPositionTicket();
      if(ticket != 0)
        {
         g_positionTicket = ticket;
         g_lastOpenDate   = StartOfDay(TimeCurrent());
        }
      else
        {
         Print("TurnaroundTuesdayEA: order sent but position ticket could not be resolved.");
        }
     }
   else
     {
      Print("TurnaroundTuesdayEA: Buy() failed. Retcode ", g_trade.ResultRetcode(),
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
      Print("TurnaroundTuesdayEA: failed to close position #", g_positionTicket,
            ". Retcode ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
     }
  }
//+------------------------------------------------------------------+
