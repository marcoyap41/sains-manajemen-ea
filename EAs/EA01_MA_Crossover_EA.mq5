//+------------------------------------------------------------------+
//|                                           MA_Crossover_EA.mq5    |
//|  Moving Average Crossover Expert Advisor for MetaTrader 5        |
//|                                                                    |
//|  Strategy (from tutorial):                                        |
//|   - Two moving averages are applied to a chart: a "slow" MA       |
//|     (long period) and a "fast" MA (short period).                 |
//|   - When the fast MA crosses ABOVE the slow MA  -> open a BUY.    |
//|   - When the fast MA crosses BELOW the slow MA  -> open a SELL.   |
//|   - Signals are evaluated once per completed (closed) bar, using  |
//|     the two most recently CLOSED bars, so the signal never        |
//|     "repaints" while a candle is still forming.                   |
//|                                                                    |
//|  Safety / robustness features added beyond the tutorial:          |
//|   - Adjustable Magic Number: the EA only ever opens, modifies or  |
//|     closes trades that carry this exact magic number, so it will  |
//|     never touch positions belonging to you or to other EAs.       |
//|   - Works on ANY symbol/timeframe it is attached to (uses         |
//|     _Symbol / _Period instead of hard-coded values).              |
//|   - No unsafe global "flags" are relied on to remember state.     |
//|     Everything the EA needs to know (open positions, indicator    |
//|     values) is re-read fresh from the terminal every time, so a   |
//|     MetaTrader restart or EA reload cannot desynchronise it.      |
//|   - Indicator handles are released properly on shutdown.          |
//|   - Basic broker "minimum stop distance" safety check before      |
//|     sending Stop Loss / Take Profit levels.                       |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"

// CTrade is a ready-made helper class (provided by MetaTrader itself)
// that makes sending/closing orders much simpler and safer than
// building raw trade requests by hand.
#include <Trade\Trade.mqh>

//--------------------------------------------------------------------
// INPUT PARAMETERS
// "input" variables appear in the EA's settings dialog in MetaTrader,
// so you can change them per chart without editing the code.
//--------------------------------------------------------------------
input long              InpMagicNumber   = 20240601; // Unique ID stamped on every trade this EA places
input double            InpLots          = 0.01;     // Trade volume (lot size) for every new position
input int               InpFastMAPeriod  = 20;       // Period of the FAST moving average
input int               InpSlowMAPeriod  = 200;      // Period of the SLOW moving average
input ENUM_MA_METHOD    InpMAMethod      = MODE_SMA; // Averaging method (Simple, Exponential, Smoothed, LWMA)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Which price the MAs are calculated from
input int               InpStopLossPts   = 200;      // Stop Loss distance, in points (0 = no Stop Loss)
input int               InpTakeProfitPts = 400;      // Take Profit distance, in points (0 = no Take Profit)
input int               InpSlippagePts   = 20;       // Maximum allowed slippage, in points
input string            InpTradeComment  = "MA Crossover EA"; // Text attached to every order

//--------------------------------------------------------------------
// GLOBAL VARIABLES
// These exist for as long as the EA is running on the chart.
//--------------------------------------------------------------------
int      g_fastHandle = INVALID_HANDLE; // "handle" (ID number) of the fast MA indicator
int      g_slowHandle = INVALID_HANDLE; // "handle" (ID number) of the slow MA indicator
datetime g_lastBarTime = 0;             // Open time of the last bar we already evaluated
CTrade   g_trade;                       // The trade-helper object we use to open/close/modify orders

//+------------------------------------------------------------------+
//| OnInit                                                            |
//| Called once: when the EA is first attached to the chart, and     |
//| again every time it is re-initialised (timeframe change, MT5     |
//| restart, recompilation, input change, etc.).                     |
//| Because everything important is rebuilt here from scratch, the   |
//| EA automatically "restores its state" after a terminal restart:  |
//| it does not depend on any value that only existed in memory.     |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Basic sanity checks on the user's inputs -------------------
   if(InpFastMAPeriod <= 0 || InpSlowMAPeriod <= 0)
     {
      Print("ERROR: MA periods must be positive integers.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpFastMAPeriod >= InpSlowMAPeriod)
     {
      Print("ERROR: Fast MA period must be smaller than Slow MA period.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpLots <= 0.0)
     {
      Print("ERROR: Lot size must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // --- Create the two moving-average indicators --------------------
   // iMA() does NOT calculate values itself; it just returns a
   // "handle", i.e. a reference number the terminal uses internally
   // to identify this exact indicator (symbol + timeframe + settings).
   g_fastHandle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, InpMAMethod, InpAppliedPrice);
   g_slowHandle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, InpMAMethod, InpAppliedPrice);

   if(g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create MA indicator handle(s). Error code: ", GetLastError());
      return(INIT_FAILED);
     }

   // --- Configure the trade helper object ---------------------------
   g_trade.SetExpertMagicNumber(InpMagicNumber); // stamp every order with our own magic number
   g_trade.SetDeviationInPoints(InpSlippagePts); // maximum acceptable slippage
   g_trade.SetTypeFillingBySymbol(_Symbol);      // let it pick a filling mode the broker/symbol supports

   // --- Initialise "last processed bar" to the CURRENT (still-forming) bar.
   // This deliberately prevents the EA from reacting to a crossover
   // signal a second time immediately after a restart/reattach; it
   // will only act again once a genuinely NEW bar opens.
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   Print("MA Crossover EA initialised on ", _Symbol, " ", EnumToString(_Period),
         " | Fast=", InpFastMAPeriod, " Slow=", InpSlowMAPeriod, " Magic=", InpMagicNumber);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//| Called whenever the EA is removed, the chart timeframe/symbol is |
//| changed, the terminal shuts down, etc. We must release the       |
//| indicator handles we created, otherwise they keep using memory.  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowHandle);
}

//+------------------------------------------------------------------+
//| Helper: does a position with OUR magic number and OUR symbol,    |
//| of the given type (BUY or SELL), currently exist?                |
//| Scanning positions fresh like this (instead of remembering a     |
//| "have I already bought" flag) is what makes the EA safe to run   |
//| alongside other EAs and safe across restarts: the real source of |
//| truth is always the broker/terminal, never our own memory.       |
//+------------------------------------------------------------------+
bool HasOpenPosition(const ENUM_POSITION_TYPE type)
{
   int total = PositionsTotal(); // how many positions exist on the whole account
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      // Only count positions that belong to THIS EA on THIS symbol.
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         return(true);
     }
   return(false);
}

//+------------------------------------------------------------------+
//| Helper: close every open position that belongs to this EA on     |
//| this symbol and matches the given type (used to flatten an       |
//| opposite position before reversing on a new signal).             |
//+------------------------------------------------------------------+
void CloseOpenPosition(const ENUM_POSITION_TYPE type)
{
   // Loop backwards: closing a position changes the numbering of the
   // remaining ones, and looping backwards avoids skipping any.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
         continue;

      if(!g_trade.PositionClose(ticket))
         Print("WARNING: Failed to close position #", ticket, " Error: ", GetLastError());
     }
}

//+------------------------------------------------------------------+
//| Helper: work out a safe Stop Loss / Take Profit price, respecting|
//| the broker's minimum stop distance so the order is never rejected|
//+------------------------------------------------------------------+
double SafeStopPrice(const double basePrice, const int points, const bool isAbove)
{
   if(points <= 0)
      return(0.0); // 0 means "no Stop Loss / Take Profit requested"

   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); // broker's minimum distance, in points
   int    usePoints = (int)MathMax(points, stopLevel + 1); // never allow a distance smaller than the broker permits

   double price = isAbove ? basePrice + usePoints * point
                           : basePrice - usePoints * point;

   return(NormalizeDouble(price, (int)_Digits));
}

//+------------------------------------------------------------------+
//| Open a BUY position (closing any opposite SELL first)            |
//+------------------------------------------------------------------+
void OpenBuy()
{
   if(HasOpenPosition(POSITION_TYPE_SELL))
      CloseOpenPosition(POSITION_TYPE_SELL);

   if(HasOpenPosition(POSITION_TYPE_BUY))
      return; // we already have a buy open, nothing more to do

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = SafeStopPrice(ask, InpStopLossPts,   false); // SL is BELOW the entry price for a buy
   double tp  = SafeStopPrice(ask, InpTakeProfitPts, true);  // TP is ABOVE the entry price for a buy

   if(!g_trade.Buy(InpLots, _Symbol, ask, sl, tp, InpTradeComment))
      Print("ERROR: Buy() failed. Error code: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Open a SELL position (closing any opposite BUY first)            |
//+------------------------------------------------------------------+
void OpenSell()
{
   if(HasOpenPosition(POSITION_TYPE_BUY))
      CloseOpenPosition(POSITION_TYPE_BUY);

   if(HasOpenPosition(POSITION_TYPE_SELL))
      return; // we already have a sell open, nothing more to do

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = SafeStopPrice(bid, InpStopLossPts,   true);  // SL is ABOVE the entry price for a sell
   double tp  = SafeStopPrice(bid, InpTakeProfitPts, false); // TP is BELOW the entry price for a sell

   if(!g_trade.Sell(InpLots, _Symbol, bid, sl, tp, InpTradeComment))
      Print("ERROR: Sell() failed. Error code: ", GetLastError());
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//| Called every time the price of the symbol changes (every "tick").|
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Step 1: only evaluate the strategy once per NEW bar ---------
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime)
      return; // still the same bar as last time we checked -> do nothing
   g_lastBarTime = currentBarTime; // remember this bar so we don't re-enter this block again until the next one

   // --- Step 2: read the last two CLOSED bars of each moving average.
   // Index 1 = the most recently closed bar, index 2 = the one before it.
   // We deliberately skip index 0 (the still-forming bar) so the
   // signal is based on confirmed, unchanging data.
   double fastMA[]; // will receive fast-MA values
   double slowMA[]; // will receive slow-MA values
   ArraySetAsSeries(fastMA, true); // index 0 = most recent value
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(g_fastHandle, 0, 1, 2, fastMA) < 2)
      return; // not enough data yet (e.g. history still loading)
   if(CopyBuffer(g_slowHandle, 0, 1, 2, slowMA) < 2)
      return;

   double fastLastClosed = fastMA[0]; // fast MA value of the most recently closed bar
   double fastPrevClosed = fastMA[1]; // fast MA value of the bar before that
   double slowLastClosed = slowMA[0]; // slow MA value of the most recently closed bar
   double slowPrevClosed = slowMA[1]; // slow MA value of the bar before that

   // --- Step 3: detect a crossover between those two closed bars ----
   bool crossedUp   = (fastPrevClosed < slowPrevClosed) && (fastLastClosed > slowLastClosed);
   bool crossedDown = (fastPrevClosed > slowPrevClosed) && (fastLastClosed < slowLastClosed);

   if(crossedUp)
     {
      Print(_Symbol, ": Fast MA crossed ABOVE Slow MA -> BUY signal");
      OpenBuy();
     }
   else if(crossedDown)
     {
      Print(_Symbol, ": Fast MA crossed BELOW Slow MA -> SELL signal");
      OpenSell();
     }
}
//+------------------------------------------------------------------+
