//+------------------------------------------------------------------+
//|                                        ATRMomentumBreakoutEA.mq5 |
//|                                                                  |
//| ATR-based momentum breakout Expert Advisor for MetaTrader 5.     |
//|                                                                  |
//| Strategy:                                                        |
//|  - On every new bar of the configurable timeframe, the EA looks  |
//|    at the candle that has just closed.                           |
//|  - If that candle's high-low range is bigger than                |
//|    InpATRMultiplier * ATR(InpATRPeriod) (ATR measured as of that |
//|    same closed candle), it is considered a "signal candle".      |
//|  - The trade direction follows the candle's own direction        |
//|    (bullish candle -> Buy, bearish candle -> Sell).               |
//|  - The candle must also close close enough to its own extreme:   |
//|    for a Buy the close must be within InpCloseProximityPercent % |
//|    of the candle's range from the high; for a Sell, within that  |
//|    same percentage from the low.                                 |
//|  - SL and TP are set as a percentage of the position's open      |
//|    (fill) price. Position size is derived from a fixed money     |
//|    risk per trade.                                                |
//|  - At most one new trade is opened per signal candle. Multiple   |
//|    positions can be open simultaneously if several signal        |
//|    candles occur while earlier trades are still running - there  |
//|    is no active trade management beyond SL/TP.                   |
//|  - A small text object is drawn above every signal candle        |
//|    showing the ATR value and the candle's size at that time.     |
//|                                                                  |
//| The EA acts only through its own, user-configurable magic        |
//| number, so it can share an account with other EAs safely. All    |
//| work is done once per new bar (not on every tick) for efficiency,|
//| and the "already traded this candle" state is kept in a          |
//| persistent terminal global variable so a MetaTrader restart      |
//| cannot cause the same signal to be traded twice.                 |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--------------------------------------------------------------------
// Inputs
//--------------------------------------------------------------------
input group "=== Identification ==="
input long             InpMagicNumber        = 20260909;      // Magic number (unique to this EA)
input string           InpTradeComment       = "ATRMomentum";  // Order/position comment prefix

input group "=== Signal ==="
input ENUM_TIMEFRAMES  InpTimeframe          = PERIOD_CURRENT; // Working timeframe
input int              InpATRPeriod          = 100;            // ATR period
input double           InpATRMultiplier      = 2.5;            // Signal candle range must exceed ATR * this
input double           InpCloseProximityPct  = 25.0;           // Close must be within this % of range from the extreme

input group "=== Risk & Targets ==="
input double           InpSLPercent          = 0.5;            // Stop-Loss, % of the position's open price
input double           InpTPPercent          = 2.0;            // Take-Profit, % of the position's open price
input double           InpRiskMoney          = 50.0;           // Fixed money risk per trade (account currency)

input group "=== Order Handling ==="
input int              InpSlippagePoints     = 20;             // Max allowed slippage/deviation, in points

input group "=== Visualization ==="
input bool             InpShowSignalLabels   = true;           // Draw a label above each signal candle

//--------------------------------------------------------------------
// Globals
//--------------------------------------------------------------------
CTrade  trade;
int     g_atrHandle   = INVALID_HANDLE;
datetime g_lastBarTime = 0;      // last bar we have evaluated (any outcome)
datetime g_lastTradeBarTime = 0; // last bar time we actually opened a trade for (restart-safe)

//+------------------------------------------------------------------+
//| Persistent (restart-safe) global variable helper                 |
//+------------------------------------------------------------------+
string GVLastTradeBarName()
  {
   return "AMB_" + (string)InpMagicNumber + "_" + _Symbol + "_" + EnumToString(InpTimeframe) + "_lastTradeBar";
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpATRPeriod <= 0 || InpATRMultiplier <= 0 || InpSLPercent <= 0 || InpRiskMoney <= 0)
     {
      Print("ATRMomentumBreakoutEA: invalid input parameters.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpCloseProximityPct < 0 || InpCloseProximityPct > 100)
     {
      Print("ATRMomentumBreakoutEA: InpCloseProximityPct must be between 0 and 100.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("ATRMomentumBreakoutEA: failed to create ATR indicator handle.");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_lastBarTime = 0;

   // Restore restart-safe "already traded this candle" state.
   string gvName = GVLastTradeBarName();
   g_lastTradeBarTime = GlobalVariableCheck(gvName) ? (datetime)GlobalVariableGet(gvName) : 0;

   DeleteAllSignalLabels();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DeleteAllSignalLabels();
  }

//+------------------------------------------------------------------+
//| Detect a new bar on the working timeframe (cheap, O(1) check)    |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime barTime = iTime(_Symbol, InpTimeframe, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return false;
   g_lastBarTime = barTime;
   return true;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Everything below runs only once per new bar - no per-tick work,
   // per the efficiency requirement.
   if(!IsNewBar())
      return;

   EvaluateSignalCandle();
  }

//+------------------------------------------------------------------+
//| Evaluate the candle that has just closed (shift 1) for a signal  |
//+------------------------------------------------------------------+
void EvaluateSignalCandle()
  {
   // Need at least InpATRPeriod+2 bars of history to be meaningful.
   if(Bars(_Symbol, InpTimeframe) < InpATRPeriod + 2)
      return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0)
      return; // indicator data not ready yet
   double atrValue = atrBuf[0];
   if(atrValue <= 0)
      return;

   double open  = iOpen(_Symbol, InpTimeframe, 1);
   double high  = iHigh(_Symbol, InpTimeframe, 1);
   double low   = iLow(_Symbol, InpTimeframe, 1);
   double close = iClose(_Symbol, InpTimeframe, 1);
   datetime signalBarTime = iTime(_Symbol, InpTimeframe, 1);

   double candleRange = high - low;
   if(candleRange <= 0)
      return;

   // Main momentum condition: the candle must be a multiple of the ATR.
   if(candleRange <= InpATRMultiplier * atrValue)
      return;

   bool bullish = close > open;
   bool bearish = close < open;
   if(!bullish && !bearish)
      return; // doji, no clear direction

   double proximityFrac = InpCloseProximityPct / 100.0;

   bool signalBuy  = false;
   bool signalSell = false;

   if(bullish)
     {
      double distFromHigh = (high - close) / candleRange;
      if(distFromHigh <= proximityFrac)
         signalBuy = true;
     }
   else // bearish
     {
      double distFromLow = (close - low) / candleRange;
      if(distFromLow <= proximityFrac)
         signalSell = true;
     }

   if(!signalBuy && !signalSell)
      return;

   // Only one trade per signal candle - and this must survive a restart.
   if(signalBarTime == g_lastTradeBarTime)
      return;

   bool opened = false;
   if(signalBuy)
      opened = OpenTrade(ORDER_TYPE_BUY);
   else if(signalSell)
      opened = OpenTrade(ORDER_TYPE_SELL);

   if(opened)
     {
      g_lastTradeBarTime = signalBarTime;
      GlobalVariableSet(GVLastTradeBarName(), (double)signalBarTime);

      if(InpShowSignalLabels)
         DrawSignalLabel(signalBarTime, high, atrValue, candleRange);
     }
  }

//+------------------------------------------------------------------+
//| Position-size calculation from a fixed money risk                |
//+------------------------------------------------------------------+
double CalcLotSize(const double slDistancePrice)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(slDistancePrice <= 0 || step <= 0)
      return minLot;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = _Point;
   if(tickValue <= 0)
      return minLot;

   double moneyPerUnitPerLot = tickValue / tickSize;
   double lossPerLot = slDistancePrice * moneyPerUnitPerLot;
   if(lossPerLot <= 0)
      return minLot;

   double lots = InpRiskMoney / lossPerLot;
   lots = MathFloor(lots / step) * step;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   int lotDigits = (int)MathRound(-MathLog10(step));
   if(lotDigits < 0) lotDigits = 0;
   return NormalizeDouble(lots, lotDigits);
  }

//+------------------------------------------------------------------+
//| Open a market position with SL/TP derived from % of entry price  |
//+------------------------------------------------------------------+
bool OpenTrade(const ENUM_ORDER_TYPE orderType)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      Print("ATRMomentumBreakoutEA: SymbolInfoTick failed.");
      return false;
     }

   double entryPrice = (orderType == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   if(entryPrice <= 0)
      return false;

   double slDist = entryPrice * (InpSLPercent / 100.0);
   double tpDist = entryPrice * (InpTPPercent / 100.0);

   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
     {
      sl = NormalizeDouble(entryPrice - slDist, digits);
      tp = InpTPPercent > 0 ? NormalizeDouble(entryPrice + tpDist, digits) : 0.0;
     }
   else
     {
      sl = NormalizeDouble(entryPrice + slDist, digits);
      tp = InpTPPercent > 0 ? NormalizeDouble(entryPrice - tpDist, digits) : 0.0;
     }

   double lots = CalcLotSize(slDist);
   string cmt = InpTradeComment + (orderType == ORDER_TYPE_BUY ? "_Buy" : "_Sell");

   bool ok;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt);
   else
      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt);

   if(!ok)
      Print("ATRMomentumBreakoutEA: order failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());

   return ok;
  }

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
string SignalObjName(const datetime barTime)
  {
   return "AMB_" + (string)InpMagicNumber + "_sig_" + (string)barTime;
  }

void DrawSignalLabel(const datetime barTime, const double candleHigh, const double atrValue, const double candleRange)
  {
   string name = SignalObjName(barTime);
   double offset = candleRange * 0.15;
   double price = candleHigh + offset;

   string text = StringFormat("ATR: %s | Size: %s",
                               DoubleToString(atrValue, _Digits),
                               DoubleToString(candleRange, _Digits));

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, barTime, price);
   else
      ObjectMove(0, name, 0, barTime, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LOWER);

   ChartRedraw(0);
  }

void DeleteAllSignalLabels()
  {
   string myPrefix = "AMB_" + (string)InpMagicNumber + "_sig_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, myPrefix) == 0)
         ObjectDelete(0, name);
     }
  }
//+------------------------------------------------------------------+
