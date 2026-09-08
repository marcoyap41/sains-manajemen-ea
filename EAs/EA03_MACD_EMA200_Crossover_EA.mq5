//+------------------------------------------------------------------+
//|                                    MACD_EMA200_Crossover_EA.mq5  |
//|                                                                    |
//| Strategy (rebuilt from a YouTube MQL5 tutorial transcript):        |
//|   - MACD(12,26,9) main/signal line crossover                      |
//|   - Crossover must occur below the zero line for BUY signals       |
//|   - Crossover must occur above the zero line for SELL signals      |
//|   - EMA(200) trend filter: price must be above EMA for BUY,        |
//|     below EMA for SELL                                             |
//|   - SL placed beyond the EMA by a small buffer, TP = SL distance   |
//|     multiplied by a configurable risk:reward ratio                 |
//|                                                                    |
//| This implementation is timeframe- and symbol-agnostic, uses its    |
//| own magic number to avoid interfering with other EAs/manual        |
//| trades, evaluates signals once per completed bar, and re-derives   |
//| its "already traded this bar" state directly from broker deal      |
//| history on every tick, so it behaves correctly after an MT5 /      |
//| terminal restart without relying on any external state file.       |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//================================= INPUTS ===================================
input group "=== Identification / Safety ==="
input long   InpMagicNumber          = 20260908;  // Magic number (unique to this EA)
input bool   InpAllowMultiplePositions = false;    // Allow more than one open position at a time
input int    InpMaxSpreadPoints      = 0;          // Max allowed spread in points (0 = no filter)
input int    InpSlippagePoints       = 20;         // Max allowed slippage / deviation in points
input string InpTradeComment         = "MACD_EMA200"; // Order comment

input group "=== Indicator Settings ==="
input int    InpFastEMA              = 12;         // MACD fast EMA period
input int    InpSlowEMA              = 26;         // MACD slow EMA period
input int    InpSignalSMA            = 9;          // MACD signal period
input int    InpMAPeriod             = 200;        // Trend filter EMA period
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Applied price for both indicators

input group "=== Risk Management ==="
input double InpSLBufferPercent      = 0.10;       // SL buffer beyond EMA, in % of price
input double InpRiskReward           = 1.5;         // Take profit = SL distance * this ratio
input bool   InpUseMoneyManagement   = false;       // Use % risk based lot sizing
input double InpRiskPercent          = 1.0;         // % of balance risked per trade (if MM enabled)
input double InpFixedLots            = 0.10;        // Fixed lot size (used if MM disabled)

input group "=== Bar-Open Timing Filter ==="
input bool   InpUseBarOpenDelay      = true;        // Wait N minutes after new bar opens before evaluating
input int    InpBarOpenDelayMinutes  = 5;           // Delay in minutes (helps avoid illiquid session-open gaps)

//================================= GLOBALS ==================================
CTrade   trade;
int      g_handleMACD  = INVALID_HANDLE;
int      g_handleMA    = INVALID_HANDLE;
datetime g_lastProcessedBar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastEMA <= 0 || InpSlowEMA <= 0 || InpSignalSMA <= 0 || InpMAPeriod <= 0)
   {
      Print("MACD_EMA200_EA: invalid indicator period input(s).");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpFastEMA >= InpSlowEMA)
   {
      Print("MACD_EMA200_EA: Fast EMA period must be smaller than Slow EMA period.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpRiskReward <= 0.0)
   {
      Print("MACD_EMA200_EA: Risk:Reward ratio must be positive.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpUseMoneyManagement && InpRiskPercent <= 0.0)
   {
      Print("MACD_EMA200_EA: Risk percent must be positive when money management is enabled.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(!InpUseMoneyManagement && InpFixedLots <= 0.0)
   {
      Print("MACD_EMA200_EA: Fixed lot size must be positive when money management is disabled.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_handleMACD = iMACD(_Symbol, PERIOD_CURRENT, InpFastEMA, InpSlowEMA, InpSignalSMA, InpAppliedPrice);
   if(g_handleMACD == INVALID_HANDLE)
   {
      Print("MACD_EMA200_EA: failed to create MACD indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   g_handleMA = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, MODE_EMA, InpAppliedPrice);
   if(g_handleMA == INVALID_HANDLE)
   {
      Print("MACD_EMA200_EA: failed to create MA indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   // Reset bar-processing state on (re)start; the real duplicate-trade guard
   // is HasOpenEntryThisBar(), which queries broker history directly, so we
   // do not need to persist g_lastProcessedBar across restarts.
   g_lastProcessedBar = 0;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handleMACD != INVALID_HANDLE)
      IndicatorRelease(g_handleMACD);
   if(g_handleMA != INVALID_HANDLE)
      IndicatorRelease(g_handleMA);
}

//+------------------------------------------------------------------+
//| Count open positions belonging to this EA on this symbol          |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Check broker deal history to see if this EA already opened a     |
//| position on the given bar. Used so state is correctly restored   |
//| after a terminal / EA restart mid-bar (no external files needed).|
//+------------------------------------------------------------------+
bool HasOpenEntryThisBar(datetime barTime)
{
   if(!HistorySelect(barTime, TimeCurrent() + 60))
      return(false);

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime >= barTime)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Basic trading-permission and market-condition checks              |
//+------------------------------------------------------------------+
bool CanTradeNow()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return(false);
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return(false);

   if(InpMaxSpreadPoints > 0)
   {
      long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPoints > InpMaxSpreadPoints)
         return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Signal enumeration                                                |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

//+------------------------------------------------------------------+
//| Evaluate the MACD + EMA200 signal on the last two completed bars  |
//+------------------------------------------------------------------+
ENUM_SIGNAL EvaluateSignal(double &maValueOut)
{
   double macdMain[2];
   double macdSignal[2];
   double maBuf[1];

   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(maBuf, true);

   if(CopyBuffer(g_handleMACD, 0, 1, 2, macdMain) < 2) return(SIGNAL_NONE);
   if(CopyBuffer(g_handleMACD, 1, 1, 2, macdSignal) < 2) return(SIGNAL_NONE);
   if(CopyBuffer(g_handleMA, 0, 1, 1, maBuf) < 1) return(SIGNAL_NONE);

   maValueOut = maBuf[0];

   // macdMain[0]/macdSignal[0] = last completed bar, [1] = the one before it
   bool crossUp   = (macdMain[0] > macdSignal[0]) && (macdMain[1] <= macdSignal[1]);
   bool crossDown = (macdMain[0] < macdSignal[0]) && (macdMain[1] >= macdSignal[1]);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return(SIGNAL_NONE);

   bool belowZero = (macdMain[0] < 0.0) && (macdSignal[0] < 0.0);
   bool aboveZero = (macdMain[0] > 0.0) && (macdSignal[0] > 0.0);

   if(crossUp && belowZero && bid > maValueOut)
      return(SIGNAL_BUY);

   if(crossDown && aboveZero && bid < maValueOut)
      return(SIGNAL_SELL);

   return(SIGNAL_NONE);
}

//+------------------------------------------------------------------+
//| Compute lot size, either fixed or risk-based                      |
//+------------------------------------------------------------------+
double ComputeLotSize(double slDistance)
{
   double lots = InpFixedLots;

   if(InpUseMoneyManagement && slDistance > 0.0)
   {
      double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tickValue > 0.0 && tickSize > 0.0)
      {
         double lossPerLot = (slDistance / tickSize) * tickValue;
         if(lossPerLot > 0.0)
            lots = riskMoney / lossPerLot;
      }
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot > 0.0)
      lots = MathFloor(lots / stepLot) * stepLot;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Attempt to open a position for the given signal                  |
//+------------------------------------------------------------------+
void TryOpenPosition(ENUM_SIGNAL signal, double maValue)
{
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = (double)stopsLvl * point;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry, sl, tp, slDistance;

   if(signal == SIGNAL_BUY)
   {
      entry = ask;
      double buffer = entry * InpSLBufferPercent / 100.0;
      sl = maValue - buffer;
      slDistance = entry - sl;
      if(slDistance < minStopDist)
      {
         slDistance = minStopDist + point;
         sl = entry - slDistance;
      }
      tp = entry + slDistance * InpRiskReward;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lots = ComputeLotSize(slDistance);
      if(lots <= 0.0)
      {
         Print("MACD_EMA200_EA: computed lot size is invalid, skipping BUY.");
         return;
      }

      if(!trade.Buy(lots, _Symbol, 0.0, sl, tp, InpTradeComment))
         Print("MACD_EMA200_EA: BUY order failed. Retcode: ", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
      else
         Print("MACD_EMA200_EA: BUY opened. Lots=", lots, " SL=", sl, " TP=", tp);
   }
   else if(signal == SIGNAL_SELL)
   {
      entry = bid;
      double buffer = entry * InpSLBufferPercent / 100.0;
      sl = maValue + buffer;
      slDistance = sl - entry;
      if(slDistance < minStopDist)
      {
         slDistance = minStopDist + point;
         sl = entry + slDistance;
      }
      tp = entry - slDistance * InpRiskReward;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lots = ComputeLotSize(slDistance);
      if(lots <= 0.0)
      {
         Print("MACD_EMA200_EA: computed lot size is invalid, skipping SELL.");
         return;
      }

      if(!trade.Sell(lots, _Symbol, 0.0, sl, tp, InpTradeComment))
         Print("MACD_EMA200_EA: SELL order failed. Retcode: ", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
      else
         Print("MACD_EMA200_EA: SELL opened. Lots=", lots, " SL=", sl, " TP=", tp);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == 0) return;

   // Already evaluated this bar -> nothing to do until the next new bar.
   if(currentBarTime == g_lastProcessedBar)
      return;

   // Optional delay after the bar opens (helps avoid thin/illiquid
   // conditions right at session or bar open, as discussed in the
   // source tutorial for higher timeframes).
   if(InpUseBarOpenDelay)
   {
      if(TimeCurrent() < currentBarTime + InpBarOpenDelayMinutes * 60)
         return;
   }

   // Mark this bar as processed regardless of outcome below, so we only
   // ever evaluate a signal once per completed bar.
   g_lastProcessedBar = currentBarTime;

   if(!CanTradeNow())
      return;

   // Restart-safe duplicate guard: even if g_lastProcessedBar was reset by
   // a restart mid-bar, we will not re-enter if the broker history shows
   // we already opened a position for this bar.
   if(HasOpenEntryThisBar(currentBarTime))
      return;

   if(!InpAllowMultiplePositions && CountOwnPositions() > 0)
      return;

   double maValue = 0.0;
   ENUM_SIGNAL signal = EvaluateSignal(maValue);

   if(signal == SIGNAL_NONE)
      return;

   TryOpenPosition(signal, maValue);
}
//+------------------------------------------------------------------+
