//+------------------------------------------------------------------+
//|                                       MarketStructureTrendEA.mq5 |
//|                                                                  |
//| Two-timeframe market-structure (swing high/low) trend-following  |
//| Expert Advisor for MetaTrader 5.                                 |
//|                                                                  |
//| Strategy:                                                        |
//|  - Swing highs/lows are detected independently on two            |
//|    timeframes: a "Trend" (higher) timeframe and a "Signal"       |
//|    (lower) timeframe. A bar is a confirmed swing high/low once   |
//|    it is strictly the highest/lowest point among InpSwingLeftBars|
//|    bars to its left and InpSwingRightBars bars to its right.     |
//|    Because a swing can only be confirmed once those bars have    |
//|    actually closed, swing points never repaint or move once      |
//|    drawn.                                                        |
//|  - Trend definition (Trend timeframe): once InpTrendConsecutive  |
//|    Swings consecutive higher swing highs AND higher swing lows   |
//|    occur, an uptrend is active; the symmetric case (consecutive  |
//|    lower highs and lower lows) defines a downtrend. While a      |
//|    trend is active, its invalidation level trails to the most    |
//|    recently confirmed swing low (uptrend) or swing high          |
//|    (downtrend). The trend ends the moment price crosses that     |
//|    level - checked every tick for a fast reaction.               |
//|  - Entries (Signal timeframe): while a Trend-timeframe trend is  |
//|    active, once InpSignalConsecutiveSwings consecutive higher    |
//|    (uptrend) or lower (downtrend) highs and lows appear on the   |
//|    Signal timeframe, a market position is opened immediately in  |
//|    the trend's direction. At most InpMaxTradesPerTrend trades    |
//|    are taken per active trend, and each distinct qualifying      |
//|    Signal-timeframe swing pattern triggers at most one trade -   |
//|    this is what stops the rapid repeated-order problem the       |
//|    strategy can otherwise suffer from.                            |
//|  - Exits: all positions in the trend's direction are closed the  |
//|    instant the Trend-timeframe trend is invalidated.             |
//|  - Position size is derived from a fixed money risk per trade.   |
//|    Stop-Loss can be set in points, in percent of the position's  |
//|    open price, or at the last Signal-timeframe swing low/high.   |
//|    Take-Profit can be set in points, in percent, or disabled.    |
//|                                                                  |
//| Efficiency: swing detection and trend/entry evaluation happen    |
//| only once per new bar on each timeframe (never on every tick);   |
//| the only per-tick work is a single price comparison to check for |
//| a trend break. On start (or restart), the EA rebuilds its swing  |
//| history and trend state directly from price history rather than  |
//| trusting fragile saved state, and persists the small amount of   |
//| state that truly cannot be recomputed (current trend direction,  |
//| trades taken in the current trend, and the last signal already   |
//| traded) in terminal global variables, so a MetaTrader restart    |
//| cannot cause duplicate trades or a lost trend.                   |
//|                                                                  |
//| The EA only ever opens, modifies, or closes trades carrying its  |
//| own (adjustable) magic number, and works on whatever symbol it   |
//| is attached to.                                                  |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

#define MAX_SWINGS_KEEP 40

//--------------------------------------------------------------------
// Enums
//--------------------------------------------------------------------
enum ENUM_SL_MODE
  {
   SL_POINTS      = 0,   // Fixed distance in points
   SL_PERCENT     = 1,   // Percent of the position's open price
   SL_LAST_SWING  = 2    // At the last Signal-timeframe swing low/high
  };

enum ENUM_TP_MODE
  {
   TP_POINTS  = 0,        // Fixed distance in points
   TP_PERCENT = 1,        // Percent of the position's open price
   TP_NONE    = 2         // No Take-Profit
  };

//--------------------------------------------------------------------
// Inputs
//--------------------------------------------------------------------
input group "=== Identification ==="
input long   InpMagicNumber          = 20260909;         // Magic number (unique to this EA)
input string InpTradeComment         = "MktStruct";       // Order/position comment prefix

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpTrendTimeframe  = PERIOD_H4;      // Higher / filter timeframe (defines the trend)
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_H1;      // Lower / signal timeframe (triggers entries)

input group "=== Swing Detection ==="
input int    InpSwingLeftBars         = 3;                // Bars required to the left of a swing point
input int    InpSwingRightBars        = 3;                // Bars required to the right of a swing point (confirmation delay)

input group "=== Trend & Entry Definition ==="
input int    InpTrendConsecutiveSwings  = 2;               // Consecutive higher/lower highs+lows to define a trend (Trend TF)
input int    InpSignalConsecutiveSwings = 1;                // Consecutive higher/lower highs+lows to trigger an entry (Signal TF)
input int    InpMaxTradesPerTrend       = 1;                // Max number of trades opened per active trend

input group "=== Risk & Targets ==="
input double         InpRiskMoney   = 50.0;               // Fixed money risk per trade (account currency)
input ENUM_SL_MODE    InpSLMode     = SL_PERCENT;          // Stop-Loss mode
input double          InpSLPoints   = 300;                 // Stop-Loss distance in points (SL_POINTS)
input double          InpSLPercent  = 1.0;                 // Stop-Loss, % of open price (SL_PERCENT)
input ENUM_TP_MODE     InpTPMode    = TP_PERCENT;          // Take-Profit mode
input double           InpTPPoints  = 900;                 // Take-Profit distance in points (TP_POINTS)
input double           InpTPPercent = 5.0;                 // Take-Profit, % of open price (TP_PERCENT)

input group "=== Order Handling ==="
input int    InpSlippagePoints        = 20;                // Max allowed slippage/deviation, in points

input group "=== History Rebuild (used on start/restart) ==="
input int    InpHistoryLookbackBars   = 3000;               // How many bars back to scan when rebuilding swing/trend state

input group "=== Visualization ==="
input bool   InpShowSwings            = true;               // Draw swing markers on the chart
input color  InpTrendHighColor        = clrRed;             // Trend-timeframe swing high color
input color  InpTrendLowColor         = clrLime;            // Trend-timeframe swing low color
input color  InpSignalHighColor       = clrOrange;          // Signal-timeframe swing high color
input color  InpSignalLowColor        = clrAqua;            // Signal-timeframe swing low color
input int    InpTrendArrowSize        = 3;                  // Trend-timeframe marker size
input int    InpSignalArrowSize       = 1;                  // Signal-timeframe marker size

//--------------------------------------------------------------------
// Types & globals
//--------------------------------------------------------------------
struct SwingState
  {
   double   highs[];
   datetime highTimes[];
   double   lows[];
   datetime lowTimes[];
   datetime lastBarTime;
  };

CTrade     trade;
SwingState g_trend;
SwingState g_signal;

int      g_trendDirection    = 0;   // 0 = none, 1 = up, -1 = down
double   g_trendInvalidLevel = 0.0;
int      g_tradesInTrend     = 0;
datetime g_lastBuySignalTime  = 0;
datetime g_lastSellSignalTime = 0;
bool     g_liveMode           = false; // false while rebuilding history on init - blocks trade entries

//+------------------------------------------------------------------+
//| Small array helpers                                              |
//+------------------------------------------------------------------+
void AppendSwing(double &arr[], datetime &times[], const double price, const datetime t, const int cap)
  {
   int n = ArraySize(arr);
   if(n >= cap)
     {
      for(int i = 0; i < n - 1; i++)
        {
         arr[i]   = arr[i + 1];
         times[i] = times[i + 1];
        }
      arr[n - 1]   = price;
      times[n - 1] = t;
     }
   else
     {
      ArrayResize(arr, n + 1);
      ArrayResize(times, n + 1);
      arr[n]   = price;
      times[n] = t;
     }
  }

bool IsIncreasing(const double &arr[], const int count)
  {
   int n = ArraySize(arr);
   if(count <= 0 || n < count + 1)
      return false;
   for(int i = n - count; i < n; i++)
      if(arr[i] <= arr[i - 1])
         return false;
   return true;
  }

bool IsDecreasing(const double &arr[], const int count)
  {
   int n = ArraySize(arr);
   if(count <= 0 || n < count + 1)
      return false;
   for(int i = n - count; i < n; i++)
      if(arr[i] >= arr[i - 1])
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Swing detection at a fixed shift (never repaints once confirmed) |
//+------------------------------------------------------------------+
bool IsSwingHighAtShift(const ENUM_TIMEFRAMES tf, const int shift, const int L, const int R)
  {
   double c = iHigh(_Symbol, tf, shift);
   for(int i = 1; i <= R; i++)
      if(iHigh(_Symbol, tf, shift - i) >= c)
         return false;
   for(int i = 1; i <= L; i++)
      if(iHigh(_Symbol, tf, shift + i) >= c)
         return false;
   return true;
  }

bool IsSwingLowAtShift(const ENUM_TIMEFRAMES tf, const int shift, const int L, const int R)
  {
   double c = iLow(_Symbol, tf, shift);
   for(int i = 1; i <= R; i++)
      if(iLow(_Symbol, tf, shift - i) <= c)
         return false;
   for(int i = 1; i <= L; i++)
      if(iLow(_Symbol, tf, shift + i) <= c)
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Persistent (restart-safe) global variable helpers                 |
//+------------------------------------------------------------------+
string GVBase()          { return "MSE_" + (string)InpMagicNumber + "_" + _Symbol + "_"; }
string GV_TrendDir()     { return GVBase() + "trendDir"; }
string GV_TradesInTrend(){ return GVBase() + "tradesInTrend"; }
string GV_LastBuy()      { return GVBase() + "lastBuy"; }
string GV_LastSell()     { return GVBase() + "lastSell"; }

double GVGetDouble(const string name, const double def)
  {
   return GlobalVariableCheck(name) ? GlobalVariableGet(name) : def;
  }

void PersistTrendState()
  {
   GlobalVariableSet(GV_TrendDir(), (double)g_trendDirection);
   GlobalVariableSet(GV_TradesInTrend(), (double)g_tradesInTrend);
  }

void PersistSignalTimes()
  {
   GlobalVariableSet(GV_LastBuy(), (double)g_lastBuySignalTime);
   GlobalVariableSet(GV_LastSell(), (double)g_lastSellSignalTime);
  }

//+------------------------------------------------------------------+
//| Drawing helpers                                                   |
//+------------------------------------------------------------------+
void DrawSwingMarker(const bool isTrendTF, const bool isHigh, const datetime t, const double price)
  {
   if(!InpShowSwings)
      return;
   string name = "MSE_" + (string)InpMagicNumber + "_" + (isTrendTF ? "T_" : "S_") + (isHigh ? "H_" : "L_") + (string)t;
   if(ObjectFind(0, name) >= 0)
      return; // swing points are final - never re-created or moved

   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isHigh ? 234 : 233);
   color clr = isTrendTF ? (isHigh ? InpTrendHighColor : InpTrendLowColor)
                         : (isHigh ? InpSignalHighColor : InpSignalLowColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, isTrendTF ? InpTrendArrowSize : InpSignalArrowSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DeleteAllDrawings()
  {
   string myPrefix = "MSE_" + (string)InpMagicNumber + "_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, myPrefix) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Trend state machine - called whenever a new Trend-TF swing forms  |
//+------------------------------------------------------------------+
void RecomputeTrend(const bool newIsHigh)
  {
   if(g_trendDirection == 0)
     {
      bool up   = IsIncreasing(g_trend.highs, InpTrendConsecutiveSwings) && IsIncreasing(g_trend.lows, InpTrendConsecutiveSwings);
      bool down = IsDecreasing(g_trend.highs, InpTrendConsecutiveSwings) && IsDecreasing(g_trend.lows, InpTrendConsecutiveSwings);
      if(up)
        {
         g_trendDirection = 1;
         int nl = ArraySize(g_trend.lows);
         g_trendInvalidLevel = g_trend.lows[nl - 1];
         g_tradesInTrend = 0;
        }
      else if(down)
        {
         g_trendDirection = -1;
         int nh = ArraySize(g_trend.highs);
         g_trendInvalidLevel = g_trend.highs[nh - 1];
         g_tradesInTrend = 0;
        }
     }
   else if(g_trendDirection == 1 && !newIsHigh)
     {
      int nl = ArraySize(g_trend.lows);
      if(nl > 0)
         g_trendInvalidLevel = g_trend.lows[nl - 1]; // trail to latest confirmed low
     }
   else if(g_trendDirection == -1 && newIsHigh)
     {
      int nh = ArraySize(g_trend.highs);
      if(nh > 0)
         g_trendInvalidLevel = g_trend.highs[nh - 1]; // trail to latest confirmed high
     }
  }

//+------------------------------------------------------------------+
//| Position-size calculation from a fixed money risk                 |
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
//| SL / TP calculation                                                |
//+------------------------------------------------------------------+
double CalcSLPrice(const ENUM_ORDER_TYPE ot, const double entryPrice)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(InpSLMode == SL_LAST_SWING)
     {
      double level;
      if(ot == ORDER_TYPE_BUY)
        {
         int nl = ArraySize(g_signal.lows);
         level = (nl > 0) ? g_signal.lows[nl - 1] : entryPrice - InpSLPoints * _Point;
        }
      else
        {
         int nh = ArraySize(g_signal.highs);
         level = (nh > 0) ? g_signal.highs[nh - 1] : entryPrice + InpSLPoints * _Point;
        }
      return NormalizeDouble(level, digits);
     }

   double dist = (InpSLMode == SL_PERCENT) ? entryPrice * (InpSLPercent / 100.0) : InpSLPoints * _Point;
   double sl = (ot == ORDER_TYPE_BUY) ? entryPrice - dist : entryPrice + dist;
   return NormalizeDouble(sl, digits);
  }

double CalcTPPrice(const ENUM_ORDER_TYPE ot, const double entryPrice)
  {
   if(InpTPMode == TP_NONE)
      return 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double dist = (InpTPMode == TP_POINTS) ? InpTPPoints * _Point : entryPrice * (InpTPPercent / 100.0);
   double tp = (ot == ORDER_TYPE_BUY) ? entryPrice + dist : entryPrice - dist;
   return NormalizeDouble(tp, digits);
  }

//+------------------------------------------------------------------+
//| Open a market position                                             |
//+------------------------------------------------------------------+
bool OpenTrade(const ENUM_ORDER_TYPE ot)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double entryPrice = (ot == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   if(entryPrice <= 0)
      return false;

   double sl = CalcSLPrice(ot, entryPrice);
   double tp = CalcTPPrice(ot, entryPrice);
   double slDist = MathAbs(entryPrice - sl);
   if(slDist <= 0)
      return false;

   double lots = CalcLotSize(slDist);
   string cmt = InpTradeComment + (ot == ORDER_TYPE_BUY ? "_Buy" : "_Sell");

   bool ok = (ot == ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt)
                                    : trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt);
   if(!ok)
      Print("MarketStructureTrendEA: order failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| Entry evaluation - called whenever a new Signal-TF swing forms    |
//+------------------------------------------------------------------+
double LatestSignalTime()
  {
   datetime th = (ArraySize(g_signal.highTimes) > 0) ? g_signal.highTimes[ArraySize(g_signal.highTimes) - 1] : 0;
   datetime tl = (ArraySize(g_signal.lowTimes)  > 0) ? g_signal.lowTimes[ArraySize(g_signal.lowTimes) - 1]  : 0;
   return (double)MathMax(th, tl);
  }

void CheckEntrySignal()
  {
   if(!g_liveMode)
      return; // never trade while rebuilding history on init
   if(g_trendDirection == 0)
      return;
   if(g_tradesInTrend >= InpMaxTradesPerTrend)
      return;

   int cnt = InpSignalConsecutiveSwings;

   if(g_trendDirection == 1)
     {
      if(!(IsIncreasing(g_signal.highs, cnt) && IsIncreasing(g_signal.lows, cnt)))
         return;
      datetime sigTime = (datetime)LatestSignalTime();
      if(sigTime <= g_lastBuySignalTime)
         return;
      if(OpenTrade(ORDER_TYPE_BUY))
        {
         g_lastBuySignalTime = sigTime;
         g_tradesInTrend++;
         PersistSignalTimes();
         PersistTrendState();
        }
     }
   else if(g_trendDirection == -1)
     {
      if(!(IsDecreasing(g_signal.highs, cnt) && IsDecreasing(g_signal.lows, cnt)))
         return;
      datetime sigTime = (datetime)LatestSignalTime();
      if(sigTime <= g_lastSellSignalTime)
         return;
      if(OpenTrade(ORDER_TYPE_SELL))
        {
         g_lastSellSignalTime = sigTime;
         g_tradesInTrend++;
         PersistSignalTimes();
         PersistTrendState();
        }
     }
  }

//+------------------------------------------------------------------+
//| Position management                                                |
//+------------------------------------------------------------------+
void CloseAllPositionsByType(const ENUM_POSITION_TYPE ptype)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != ptype) continue;
      if(!trade.PositionClose(ticket))
         Print("MarketStructureTrendEA: failed to close position #", ticket, " retcode=", trade.ResultRetcode());
     }
  }

void CheckTrendBreak()
  {
   if(g_trendDirection == 0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(g_trendDirection == 1 && bid < g_trendInvalidLevel)
     {
      CloseAllPositionsByType(POSITION_TYPE_BUY);
      g_trendDirection = 0;
      g_tradesInTrend  = 0;
      PersistTrendState();
     }
   else if(g_trendDirection == -1 && bid > g_trendInvalidLevel)
     {
      CloseAllPositionsByType(POSITION_TYPE_SELL);
      g_trendDirection = 0;
      g_tradesInTrend  = 0;
      PersistTrendState();
     }
  }

//+------------------------------------------------------------------+
//| Core swing-candidate processing, shared by live ticks and the    |
//| one-time history rebuild                                          |
//+------------------------------------------------------------------+
void ProcessCandidateShift(SwingState &st, const ENUM_TIMEFRAMES tf, const bool isTrendTF, const int shift)
  {
   int L = InpSwingLeftBars, R = InpSwingRightBars;

   bool foundHigh = IsSwingHighAtShift(tf, shift, L, R);
   bool foundLow  = IsSwingLowAtShift(tf, shift, L, R);

   if(foundHigh)
     {
      datetime t = iTime(_Symbol, tf, shift);
      double   p = iHigh(_Symbol, tf, shift);
      AppendSwing(st.highs, st.highTimes, p, t, MAX_SWINGS_KEEP);
      DrawSwingMarker(isTrendTF, true, t, p);
      if(isTrendTF)
         RecomputeTrend(true);
     }
   if(foundLow)
     {
      datetime t = iTime(_Symbol, tf, shift);
      double   p = iLow(_Symbol, tf, shift);
      AppendSwing(st.lows, st.lowTimes, p, t, MAX_SWINGS_KEEP);
      DrawSwingMarker(isTrendTF, false, t, p);
      if(isTrendTF)
         RecomputeTrend(false);
     }
   if(!isTrendTF && (foundHigh || foundLow))
      CheckEntrySignal();
  }

//+------------------------------------------------------------------+
//| Live per-tick, per-timeframe new-bar handling (cheap when no new  |
//| bar has formed)                                                    |
//+------------------------------------------------------------------+
void CheckNewBarAndProcess(SwingState &st, const ENUM_TIMEFRAMES tf, const bool isTrendTF)
  {
   datetime bt = iTime(_Symbol, tf, 0);
   if(bt == 0 || bt == st.lastBarTime)
      return;
   st.lastBarTime = bt;

   int candidateShift = InpSwingRightBars + 1;
   if(Bars(_Symbol, tf) < candidateShift + InpSwingLeftBars + 1)
      return;

   ProcessCandidateShift(st, tf, isTrendTF, candidateShift);
   if(isTrendTF)
      PersistTrendState();
  }

//+------------------------------------------------------------------+
//| One-time rebuild of swing/trend state from price history          |
//| (used on init / after a restart so nothing needs to be trusted    |
//| from fragile saved state)                                          |
//+------------------------------------------------------------------+
void RebuildHistory(SwingState &st, const ENUM_TIMEFRAMES tf, const bool isTrendTF)
  {
   ArrayFree(st.highs);
   ArrayFree(st.highTimes);
   ArrayFree(st.lows);
   ArrayFree(st.lowTimes);

   int L = InpSwingLeftBars, R = InpSwingRightBars;
   int totalBars = Bars(_Symbol, tf);
   int maxShift = MathMin(InpHistoryLookbackBars, totalBars - L - 1);

   if(maxShift < R + 1)
     {
      st.lastBarTime = iTime(_Symbol, tf, 0);
      return;
     }

   for(int shift = maxShift; shift >= R + 1; shift--)
      ProcessCandidateShift(st, tf, isTrendTF, shift);

   st.lastBarTime = iTime(_Symbol, tf, 0);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSwingLeftBars <= 0 || InpSwingRightBars <= 0 ||
      InpTrendConsecutiveSwings <= 0 || InpSignalConsecutiveSwings <= 0 ||
      InpMaxTradesPerTrend <= 0 || InpRiskMoney <= 0 || InpHistoryLookbackBars <= 0)
     {
      Print("MarketStructureTrendEA: invalid input parameters.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_liveMode = false;
   g_trendDirection = 0;
   g_trendInvalidLevel = 0.0;
   g_tradesInTrend = 0;

   // Rebuild swing history and replay the trend state machine from
   // price history - deterministic and restart-safe by construction.
   RebuildHistory(g_trend, InpTrendTimeframe, true);
   RebuildHistory(g_signal, InpSignalTimeframe, false);

   // Reconcile the few facts that cannot be recomputed from price
   // alone: how many trades were already taken in the CURRENT trend,
   // and which signals were already acted upon.
   int persistedDir = (int)GVGetDouble(GV_TrendDir(), 0);
   if(g_trendDirection == persistedDir)
      g_tradesInTrend = (int)GVGetDouble(GV_TradesInTrend(), 0);
   else
      g_tradesInTrend = 0;

   g_lastBuySignalTime  = (datetime)GVGetDouble(GV_LastBuy(), 0);
   g_lastSellSignalTime = (datetime)GVGetDouble(GV_LastSell(), 0);

   PersistTrendState();

   g_liveMode = true;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteAllDrawings();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Checked every tick for a fast reaction - just one comparison.
   CheckTrendBreak();

   // Swing detection / trend / entry evaluation only run once per new
   // bar on each timeframe.
   CheckNewBarAndProcess(g_trend, InpTrendTimeframe, true);
   CheckNewBarAndProcess(g_signal, InpSignalTimeframe, false);
  }
//+------------------------------------------------------------------+
