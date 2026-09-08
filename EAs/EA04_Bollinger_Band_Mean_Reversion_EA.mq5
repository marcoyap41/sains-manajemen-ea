//+------------------------------------------------------------------+
//|                                         BB_MA_Filter_EA.mq5       |
//|                                                                    |
//|  Strategy (reconstructed from tutorial transcript):                |
//|   - Bollinger Bands mean-reversion entries:                        |
//|       SELL when price touches/exceeds the UPPER band               |
//|       BUY  when price touches/exceeds the LOWER band                |
//|   - Optional Moving Average trend filter (own timeframe/period):    |
//|       SELL only allowed if filter is off OR Bid < MA                |
//|       BUY  only allowed if filter is off OR Ask > MA                |
//|   - SL/TP distance = Bollinger Band width (Upper-Lower) at signal   |
//|     time, multiplied by independent SL/TP factors                  |
//|   - Exit / partial close: when price crosses back through the      |
//|     BB basis (middle) line, ClosePercent % of the position volume  |
//|     is closed (100% = full close, matching the tutorial's demo of  |
//|     turning a full close into a partial close via one input)       |
//|   - One position per symbol per magic number at a time             |
//|   - State (partial-close-done flag) restored after MT5 restart     |
//|     via terminal GlobalVariables keyed by position ticket          |
//+------------------------------------------------------------------+
#property copyright "marcoyap41 "
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--------------------------------------------------------------------
// Inputs
//--------------------------------------------------------------------
input group "General"
input long             InpMagic          = 20260908;    // Magic Number
input double            InpLots           = 0.10;        // Lot size
input int                InpSlippagePoints = 30;          // Max slippage (points)
input string             InpTradeComment   = "BB_MA_EA";  // Trade comment

input group "Bollinger Bands"
input ENUM_TIMEFRAMES    InpBBTimeframe    = PERIOD_H1;   // BB timeframe
input int                InpBBPeriod       = 20;          // BB period
input int                InpBBShift        = 0;           // BB shift
input double             InpBBDeviation    = 2.0;         // BB deviation
input ENUM_APPLIED_PRICE InpBBAppliedPrice = PRICE_CLOSE;  // BB applied price

input group "Moving Average Filter"
input bool                InpUseMAFilter    = true;        // Use MA filter
input ENUM_TIMEFRAMES     InpMATimeframe    = PERIOD_H4;    // MA timeframe
input int                 InpMAPeriod       = 50;           // MA period
input int                 InpMAShift        = 0;            // MA shift
input ENUM_MA_METHOD      InpMAMethod       = MODE_SMA;      // MA method
input ENUM_APPLIED_PRICE  InpMAAppliedPrice = PRICE_CLOSE;   // MA applied price

input group "Risk Management"
input double InpSLFactor      = 2.0;   // SL factor (x Band width)
input double InpTPFactor      = 0.5;   // TP factor (x Band width)
input double InpClosePercent  = 30.0;  // % of position to close at basis-line exit (100 = full close)

//--------------------------------------------------------------------
// Globals
//--------------------------------------------------------------------
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

int      hBB   = INVALID_HANDLE;
int      hMA   = INVALID_HANDLE;

datetime lastBarTime = 0;

#define GV_PREFIX "BB_MA_EA_PC_"   // global-variable prefix for partial-close flags

//+------------------------------------------------------------------+
//| Build the unique GlobalVariable name for a ticket                |
//+------------------------------------------------------------------+
string PartialCloseGVName(const ulong ticket)
  {
   return GV_PREFIX + IntegerToString((long)InpMagic) + "_" + IntegerToString((long)ticket);
  }

//+------------------------------------------------------------------+
//| Has this ticket already had its partial close executed?          |
//+------------------------------------------------------------------+
bool IsPartialClosed(const ulong ticket)
  {
   return GlobalVariableCheck(PartialCloseGVName(ticket));
  }

//+------------------------------------------------------------------+
//| Mark a ticket as partial-closed (persists across MT5 restarts)   |
//+------------------------------------------------------------------+
void SetPartialClosed(const ulong ticket)
  {
   GlobalVariableSet(PartialCloseGVName(ticket), 1.0);
  }

//+------------------------------------------------------------------+
//| Remove the flag once a position no longer exists                 |
//+------------------------------------------------------------------+
void ClearPartialClosedFlag(const ulong ticket)
  {
   string name = PartialCloseGVName(ticket);
   if(GlobalVariableCheck(name))
      GlobalVariableDel(name);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!symInfo.Name(_Symbol))
     {
      Print("Failed to initialize symbol info for ", _Symbol);
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   hBB = iBands(_Symbol, InpBBTimeframe, InpBBPeriod, InpBBShift, InpBBDeviation, InpBBAppliedPrice);
   if(hBB == INVALID_HANDLE)
     {
      Print("Failed to create Bollinger Bands handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }

   if(InpUseMAFilter)
     {
      hMA = iMA(_Symbol, InpMATimeframe, InpMAPeriod, InpMAShift, InpMAMethod, InpMAAppliedPrice);
      if(hMA == INVALID_HANDLE)
        {
         Print("Failed to create Moving Average handle. Error: ", GetLastError());
         return(INIT_FAILED);
        }
     }

   if(InpClosePercent <= 0.0 || InpClosePercent > 100.0)
     {
      Print("InpClosePercent must be within (0, 100]. Current value: ", InpClosePercent);
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Restore state on restart: reconcile any stale global-variable flags
   // for tickets that no longer have an open position belonging to us.
   ReconcilePartialCloseFlags();

   lastBarTime = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hBB != INVALID_HANDLE)
      IndicatorRelease(hBB);
   if(hMA != INVALID_HANDLE)
      IndicatorRelease(hMA);
  }

//+------------------------------------------------------------------+
//| On every tick                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!symInfo.RefreshRates())
      return;

   // Manage any existing position for this symbol/magic on every tick
   // (partial close reacts as soon as price crosses the basis line).
   ManageOpenPosition();

   // Entries are only evaluated once per new bar on the BB timeframe,
   // to avoid re-triggering the same signal repeatedly on every tick.
   datetime curBarTime = iTime(_Symbol, InpBBTimeframe, 0);
   if(curBarTime == 0 || curBarTime == lastBarTime)
      return;
   lastBarTime = curBarTime;

   if(HasOpenPosition())
      return; // one position per symbol/magic at a time

   CheckForEntry();
  }

//+------------------------------------------------------------------+
//| Does a position with our magic number already exist here?        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   if(!PositionSelect(_Symbol))
      return(false);
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Read one Bollinger Bands value set at the given shift (0=current)|
//+------------------------------------------------------------------+
bool GetBands(const int shift, double &upperOut, double &lowerOut, double &basisOut)
  {
   double upperBuf[], lowerBuf[], basisBuf[];
   ArraySetAsSeries(upperBuf, true);
   ArraySetAsSeries(lowerBuf, true);
   ArraySetAsSeries(basisBuf, true);

   if(CopyBuffer(hBB, 1, shift, 1, upperBuf) <= 0) // UPPER_BAND
      return(false);
   if(CopyBuffer(hBB, 2, shift, 1, lowerBuf) <= 0) // LOWER_BAND
      return(false);
   if(CopyBuffer(hBB, 0, shift, 1, basisBuf) <= 0) // BASE_LINE
      return(false);

   upperOut = upperBuf[0];
   lowerOut = lowerBuf[0];
   basisOut = basisBuf[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| Read the MA value at the given shift (0=current)                 |
//+------------------------------------------------------------------+
bool GetMA(const int shift, double &maOut)
  {
   if(hMA == INVALID_HANDLE)
     {
      maOut = 0.0;
      return(true);
     }
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hMA, 0, shift, 1, buf) <= 0)
      return(false);
   maOut = buf[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| Evaluate and, if valid, execute an entry signal                  |
//+------------------------------------------------------------------+
void CheckForEntry()
  {
   double upper, lower, basis;
   if(!GetBands(1, upper, lower, basis)) // use last CLOSED bar to avoid repainting
      return;

   double ma = 0.0;
   if(InpUseMAFilter)
     {
      if(!GetMA(1, ma))
         return;
     }

   double bid = symInfo.Bid();
   double ask = symInfo.Ask();
   double bandWidth = upper - lower;
   if(bandWidth <= 0.0)
      return;

   // SELL signal: price at/above the upper band
   if(bid >= upper)
     {
      bool filterOk = (!InpUseMAFilter) || (bid < ma);
      if(filterOk)
        {
         OpenPosition(ORDER_TYPE_SELL, bandWidth);
         return;
        }
     }

   // BUY signal: price at/below the lower band
   if(ask <= lower)
     {
      bool filterOk = (!InpUseMAFilter) || (ask > ma);
      if(filterOk)
        {
         OpenPosition(ORDER_TYPE_BUY, bandWidth);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Normalize a price to the symbol's tick size / digits             |
//+------------------------------------------------------------------+
double NormalizePriceValue(const double price)
  {
   double tickSize = symInfo.TickSize();
   if(tickSize <= 0.0)
      return(NormalizeDouble(price, symInfo.Digits()));
   double normalized = MathRound(price / tickSize) * tickSize;
   return(NormalizeDouble(normalized, symInfo.Digits()));
  }

//+------------------------------------------------------------------+
//| Open a new position with SL/TP derived from band width * factors |
//+------------------------------------------------------------------+
void OpenPosition(const ENUM_ORDER_TYPE orderType, const double bandWidth)
  {
   double slDistance = bandWidth * InpSLFactor;
   double tpDistance = bandWidth * InpTPFactor;

   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * symInfo.Point();
   if(slDistance < stopLevel && stopLevel > 0.0)
      slDistance = stopLevel;
   if(tpDistance < stopLevel && stopLevel > 0.0)
      tpDistance = stopLevel;

   double price, sl, tp;

   if(orderType == ORDER_TYPE_BUY)
     {
      price = symInfo.Ask();
      sl    = NormalizePriceValue(price - slDistance);
      tp    = NormalizePriceValue(price + tpDistance);
      if(!trade.Buy(NormalizeLots(InpLots), _Symbol, price, sl, tp, InpTradeComment))
         Print("Buy order failed. Error: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
     }
   else
     {
      price = symInfo.Bid();
      sl    = NormalizePriceValue(price + slDistance);
      tp    = NormalizePriceValue(price - tpDistance);
      if(!trade.Sell(NormalizeLots(InpLots), _Symbol, price, sl, tp, InpTradeComment))
         Print("Sell order failed. Error: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Clamp/normalize a lot size to the symbol's volume constraints    |
//+------------------------------------------------------------------+
double NormalizeLots(const double lots)
  {
   double minVol  = symInfo.LotsMin();
   double maxVol  = symInfo.LotsMax();
   double stepVol = symInfo.LotsStep();

   double result = lots;
   if(stepVol > 0.0)
      result = MathRound(result / stepVol) * stepVol;
   if(result < minVol)
      result = minVol;
   if(result > maxVol)
      result = maxVol;
   return(NormalizeDouble(result, 2));
  }

//+------------------------------------------------------------------+
//| Manage an existing position: partial close at the basis line     |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   if(!PositionSelect(_Symbol))
      return;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   if(IsPartialClosed(ticket))
      return;

   double upper, lower, basis;
   if(!GetBands(0, upper, lower, basis))
      return;

   long   posType   = PositionGetInteger(POSITION_TYPE);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   double bid        = symInfo.Bid();
   double ask        = symInfo.Ask();

   bool triggered = false;

   if(posType == POSITION_TYPE_BUY && bid >= basis)
      triggered = true;
   else
      if(posType == POSITION_TYPE_SELL && ask <= basis)
         triggered = true;

   if(!triggered)
      return;

   if(InpClosePercent >= 100.0)
     {
      if(trade.PositionClose(_Symbol))
         SetPartialClosed(ticket); // will be cleared on next reconciliation once position is gone
      else
         Print("Full close at basis line failed. Error: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
      return;
     }

   double closeVolume = NormalizeLots(volume * (InpClosePercent / 100.0));
   double minVol = symInfo.LotsMin();
   if(closeVolume < minVol)
      closeVolume = minVol;
   if(closeVolume >= volume)
     {
      if(trade.PositionClose(_Symbol))
         SetPartialClosed(ticket);
      else
         Print("Close at basis line failed. Error: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
      return;
     }

   if(trade.PositionClosePartial(_Symbol, closeVolume))
      SetPartialClosed(ticket);
   else
      Print("Partial close at basis line failed. Error: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| On any trade transaction: clean up flags for closed positions    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   if((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   // If the position is fully gone now, clear its flag so the GV store
   // doesn't grow unbounded and so a reused ticket id starts clean.
   if(!PositionSelectByTicket(positionId))
      ClearPartialClosedFlag(positionId);
  }

//+------------------------------------------------------------------+
//| On startup, drop any partial-close flags whose positions are gone|
//| (keeps the terminal's GlobalVariable store tidy after a restart) |
//+------------------------------------------------------------------+
void ReconcilePartialCloseFlags()
  {
   string prefix = GV_PREFIX + IntegerToString((long)InpMagic) + "_";
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue;

      string ticketStr = StringSubstr(name, StringLen(prefix));
      ulong  ticket = (ulong)StringToInteger(ticketStr);

      if(!PositionSelectByTicket(ticket))
         GlobalVariableDel(name);
     }
  }
//+------------------------------------------------------------------+
