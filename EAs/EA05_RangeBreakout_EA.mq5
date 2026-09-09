//+------------------------------------------------------------------+
//|                                            RangeBreakoutEA.mq5   |
//|                                                                  |
//| Time-based range breakout Expert Advisor for MetaTrader 5.       |
//|                                                                  |
//| Strategy:                                                        |
//|  - Every trading session, a price range is built between         |
//|    InpRangeStartHour:Minute and InpRangeEndHour:Minute.          |
//|  - Once the range is complete, a Buy Stop is placed at the       |
//|    range high and a Sell Stop at the range low (subject to       |
//|    InpTradeMode). If price has already broken out of the range   |
//|    by the time orders are placed, a market order is opened       |
//|    instead of an invalid pending order.                          |
//|  - SL/TP are derived from the range size multiplied by the       |
//|    configurable Stop-Loss / Take-Profit factors. TP is optional. |
//|  - Optionally, at InpCloseHour:Minute all pending orders for      |
//|    this EA are removed and all open positions for this EA are    |
//|    closed, and no further trades are opened until the next       |
//|    session.                                                      |
//|  - Optionally (InpOneTradePerDay), as soon as one side of the    |
//|    pair fills, the opposite pending order is cancelled (OCO).    |
//|                                                                  |
//| The EA identifies its own trades exclusively through             |
//| InpMagicNumber, works on whatever symbol/chart it is attached    |
//| to, and restores its daily state (already-placed / already-      |
//| closed flags) via persistent terminal global variables, so a     |
//| restart of MetaTrader 5 will not cause duplicate orders or       |
//| repeated forced closes on the same trading day.                  |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--------------------------------------------------------------------
// Inputs
//--------------------------------------------------------------------
enum ENUM_TRADE_MODE
  {
   TRADE_BOTH      = 0,   // Trade both sides (Buy Stop + Sell Stop)
   TRADE_BUY_ONLY  = 1,   // Trade Buy side only
   TRADE_SELL_ONLY = 2    // Trade Sell side only
  };

input group "=== Identification ==="
input long   InpMagicNumber      = 20260909;   // Magic number (unique to this EA)
input string InpTradeComment     = "RangeBO";  // Order/position comment prefix

input group "=== Range Window ==="
input int    InpRangeStartHour   = 3;          // Range start hour   (0-23, broker/server time)
input int    InpRangeStartMinute = 0;          // Range start minute (0-59)
input int    InpRangeEndHour     = 6;          // Range end hour     (0-23)
input int    InpRangeEndMinute   = 0;          // Range end minute   (0-59)

input group "=== Session Close ==="
input bool   InpUseCloseTime     = true;       // Force-close positions / delete pending orders at a fixed time
input int    InpCloseHour        = 23;         // Close hour   (0-23) - ignored if InpUseCloseTime=false
input int    InpCloseMinute      = 0;          // Close minute (0-59)

input group "=== Risk & Targets ==="
input double InpRiskMoney        = 50.0;       // Fixed money risk per trade (account currency)
input double InpSLFactor         = 1.0;        // Stop-Loss  = range size * this factor
input bool   InpUseTP            = true;       // Use a Take-Profit at all
input double InpTPFactor         = 1.0;        // Take-Profit = range size * this factor (if InpUseTP)

input group "=== Trade Selection ==="
input ENUM_TRADE_MODE InpTradeMode     = TRADE_BOTH; // Which side(s) to trade
input bool             InpOneTradePerDay = false;    // Cancel the opposite pending order once one side fills

input group "=== Order Handling ==="
input int    InpSlippagePoints   = 20;         // Max allowed slippage/deviation, in points
input double InpPendingBufferPts = 0;          // Extra buffer (points) added beyond range high/low for pending orders

input group "=== Visualization ==="
input bool   InpVisualizeRange   = true;       // Draw the range rectangle/lines on the chart
input bool   InpDeleteOldRanges  = true;       // Delete previous sessions' drawings when a new one starts

//--------------------------------------------------------------------
// Globals
//--------------------------------------------------------------------
CTrade  trade;

string   g_currentDayKey = "";   // Identifies the active trading session (date of its range start)
datetime g_rangeStart    = 0;
datetime g_rangeEnd      = 0;
datetime g_closeTime     = 0;
bool     g_ordersPlaced  = false;
bool     g_dayClosed     = false;
datetime g_lastM1BarTime = 0;    // throttle for the live (in-progress) range drawing

//+------------------------------------------------------------------+
//| Persistent (restart-safe) global variable helpers                |
//+------------------------------------------------------------------+
string GVPrefix()
  {
   return "RBEA_" + (string)InpMagicNumber + "_" + _Symbol + "_";
  }

string GVPlacedName(const string dayKey) { return GVPrefix() + "placed_"  + dayKey; }
string GVClosedName(const string dayKey) { return GVPrefix() + "closed_"  + dayKey; }

bool GVGetBool(const string name)
  {
   if(!GlobalVariableCheck(name))
      return false;
   return GlobalVariableGet(name) != 0.0;
  }

void GVSetBool(const string name, const bool value)
  {
   GlobalVariableSet(name, value ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRangeStartHour < 0 || InpRangeStartHour > 23 || InpRangeEndHour < 0 || InpRangeEndHour > 23 ||
      InpRangeStartMinute < 0 || InpRangeStartMinute > 59 || InpRangeEndMinute < 0 || InpRangeEndMinute > 59)
     {
      Print("RangeBreakoutEA: invalid range time inputs.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpSLFactor <= 0)
     {
      Print("RangeBreakoutEA: InpSLFactor must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskMoney <= 0)
     {
      Print("RangeBreakoutEA: InpRiskMoney must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_currentDayKey = "";   // forces a fresh session evaluation on the very first tick

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Compute the boundaries of the session that "owns" time 'now'     |
//+------------------------------------------------------------------+
void ComputeSessionTimes(const datetime now, datetime &rangeStart, datetime &rangeEnd, datetime &closeTime, string &dayKey)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayAnchor = StructToTime(dt);

   long startSec = InpRangeStartHour * 3600L + InpRangeStartMinute * 60L;
   long endSec   = InpRangeEndHour   * 3600L + InpRangeEndMinute   * 60L;
   long closeSec = InpCloseHour      * 3600L + InpCloseMinute      * 60L;

   rangeStart = dayAnchor + startSec;

   // If 'now' is earlier than today's range start, 'now' still belongs to
   // the previous session (which may run past midnight, e.g. overnight close).
   if(now < rangeStart)
     {
      dayAnchor -= 86400;
      rangeStart = dayAnchor + startSec;
     }

   rangeEnd = dayAnchor + endSec;
   if(rangeEnd <= rangeStart)
      rangeEnd += 86400;

   if(InpUseCloseTime)
     {
      closeTime = dayAnchor + closeSec;
      if(closeTime <= rangeEnd)
         closeTime += 86400;
     }
   else
      closeTime = 0;

   dayKey = TimeToString(rangeStart, TIME_DATE);
  }

//+------------------------------------------------------------------+
//| Load / reset state for a (possibly new) trading session          |
//+------------------------------------------------------------------+
void LoadSession(const string dayKey, const datetime rangeStart, const datetime rangeEnd, const datetime closeTime)
  {
   g_currentDayKey = dayKey;
   g_rangeStart    = rangeStart;
   g_rangeEnd      = rangeEnd;
   g_closeTime     = closeTime;
   g_ordersPlaced  = GVGetBool(GVPlacedName(dayKey));
   g_dayClosed     = GVGetBool(GVClosedName(dayKey));
   g_lastM1BarTime = 0;

   if(InpVisualizeRange && InpDeleteOldRanges)
      DeleteRangeDrawings("__old__"); // clears anything not matching current key below
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   datetime rangeStart, rangeEnd, closeTime;
   string   dayKey;
   ComputeSessionTimes(now, rangeStart, rangeEnd, closeTime, dayKey);

   if(dayKey != g_currentDayKey)
      LoadSession(dayKey, rangeStart, rangeEnd, closeTime);

   // Still before the range starts: nothing to do this tick.
   if(now < g_rangeStart)
      return;

   // Inside the range-building window.
   if(now < g_rangeEnd)
     {
      if(InpVisualizeRange)
         UpdateLiveRangeDrawing();
      return;
     }

   // Range window has finished: place the initial orders once.
   if(!g_ordersPlaced && !g_dayClosed)
     {
      if(ComputeAndPlaceOrders())
        {
         g_ordersPlaced = true;
         GVSetBool(GVPlacedName(g_currentDayKey), true);
        }
     }

   // Forced session close.
   if(InpUseCloseTime && !g_dayClosed && now >= g_closeTime)
     {
      ForceCloseSession();
      g_dayClosed = true;
      GVSetBool(GVClosedName(g_currentDayKey), true);
     }
  }

//+------------------------------------------------------------------+
//| React immediately to fills for OCO management (efficient,       |
//| event-driven instead of polling every tick)                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!InpOneTradePerDay || InpTradeMode != TRADE_BOTH)
      return;
   if(trans.symbol != _Symbol)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;

   // One side has just opened a position: cancel any remaining pending order.
   if(HasOpenPosition())
      DeleteAllPendingOrders();
  }

//+------------------------------------------------------------------+
//| Compute the range high/low from M1 history                       |
//+------------------------------------------------------------------+
bool CalcRangeHighLow(const datetime start, const datetime end, double &outHigh, double &outLow)
  {
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, start, end, rates);
   if(copied <= 0)
     {
      Print("RangeBreakoutEA: could not read M1 history for range calculation (copied=", copied, ").");
      return false;
     }

   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 0; i < copied; i++)
     {
      if(rates[i].high > hi) hi = rates[i].high;
      if(rates[i].low  < lo) lo = rates[i].low;
     }
   outHigh = hi;
   outLow  = lo;
   return true;
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
//| Build the range, draw it, and place the entry orders             |
//+------------------------------------------------------------------+
bool ComputeAndPlaceOrders()
  {
   double rHigh, rLow;
   if(!CalcRangeHighLow(g_rangeStart, g_rangeEnd, rHigh, rLow))
      return false;

   double rangeSize = rHigh - rLow;
   if(rangeSize <= 0)
     {
      Print("RangeBreakoutEA: computed range size is not positive, skipping this session.");
      return true; // nothing more we can do this session; mark as handled
     }

   if(InpVisualizeRange)
      DrawRange(g_rangeStart, g_rangeEnd, rHigh, rLow);

   double slDist = rangeSize * InpSLFactor;
   double tpDist = InpUseTP ? rangeSize * InpTPFactor : 0.0;

   bool doBuy  = (InpTradeMode == TRADE_BOTH || InpTradeMode == TRADE_BUY_ONLY);
   bool doSell = (InpTradeMode == TRADE_BOTH || InpTradeMode == TRADE_SELL_ONLY);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      Print("RangeBreakoutEA: SymbolInfoTick failed.");
      return false;
     }

   if(doBuy)
      PlaceBuySide(rHigh, slDist, tpDist, tick.ask);
   if(doSell)
      PlaceSellSide(rLow, slDist, tpDist, tick.bid);

   return true;
  }

//+------------------------------------------------------------------+
//| Buy side: pending Buy Stop, or market Buy if already broken out  |
//+------------------------------------------------------------------+
void PlaceBuySide(const double rangeHigh, const double slDist, const double tpDist, const double ask)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpPendingBufferPts * _Point;
   double entryLevel = NormalizeDouble(rangeHigh + buffer, digits);

   string cmt = InpTradeComment + "_Buy_" + g_currentDayKey;

   if(ask > entryLevel)
     {
      // Breakout already happened: a Buy Stop below/at market would be invalid.
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = tpDist > 0 ? NormalizeDouble(ask + tpDist, digits) : 0.0;
      double lots = CalcLotSize(slDist);
      if(!trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt))
         Print("RangeBreakoutEA: market Buy failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
   else
     {
      double sl = NormalizeDouble(entryLevel - slDist, digits);
      double tp = tpDist > 0 ? NormalizeDouble(entryLevel + tpDist, digits) : 0.0;
      double lots = CalcLotSize(slDist);
      if(!trade.BuyStop(lots, entryLevel, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt))
         Print("RangeBreakoutEA: BuyStop failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Sell side: pending Sell Stop, or market Sell if already broken   |
//+------------------------------------------------------------------+
void PlaceSellSide(const double rangeLow, const double slDist, const double tpDist, const double bid)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpPendingBufferPts * _Point;
   double entryLevel = NormalizeDouble(rangeLow - buffer, digits);

   string cmt = InpTradeComment + "_Sell_" + g_currentDayKey;

   if(bid < entryLevel)
     {
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = tpDist > 0 ? NormalizeDouble(bid - tpDist, digits) : 0.0;
      double lots = CalcLotSize(slDist);
      if(!trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt))
         Print("RangeBreakoutEA: market Sell failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
   else
     {
      double sl = NormalizeDouble(entryLevel + slDist, digits);
      double tp = tpDist > 0 ? NormalizeDouble(entryLevel - tpDist, digits) : 0.0;
      double lots = CalcLotSize(slDist);
      if(!trade.SellStop(lots, entryLevel, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt))
         Print("RangeBreakoutEA: SellStop failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Does this EA currently have an open position on this symbol?     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Delete every pending order belonging to this EA on this symbol   |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(!trade.OrderDelete(ticket))
         Print("RangeBreakoutEA: failed to delete order #", ticket, " retcode=", trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| Close every open position belonging to this EA on this symbol    |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(!trade.PositionClose(ticket))
         Print("RangeBreakoutEA: failed to close position #", ticket, " retcode=", trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| End of session: cancel pendings, close positions, stop trading   |
//| for the remainder of this session                                |
//+------------------------------------------------------------------+
void ForceCloseSession()
  {
   DeleteAllPendingOrders();
   CloseAllPositions();
  }

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
string RangeObjPrefix()
  {
   return "RBEA_" + (string)InpMagicNumber + "_" + g_currentDayKey + "_";
  }

void DeleteRangeDrawings(const string unusedKey)
  {
   // Remove any range drawings from this EA that do not belong to the
   // brand-new session about to start (i.e. every previous session's set).
   string myTagPrefix = "RBEA_" + (string)InpMagicNumber + "_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, myTagPrefix) == 0)
         ObjectDelete(0, name);
     }
  }

void DrawRange(const datetime start, const datetime end, const double high, const double low)
  {
   string prefix = RangeObjPrefix();
   string rectName = prefix + "rect";
   string hiName   = prefix + "hi";
   string loName   = prefix + "lo";

   if(ObjectFind(0, rectName) < 0)
      ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, start, high, end, low);
   else
     {
      ObjectMove(0, rectName, 0, start, high);
      ObjectMove(0, rectName, 1, end, low);
     }
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);

   DrawHLineSegment(hiName, start, end, high, clrDodgerBlue);
   DrawHLineSegment(loName, start, end, low,  clrOrangeRed);

   ChartRedraw(0);
  }

void DrawHLineSegment(const string name, const datetime start, const datetime end, const double price, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, start, price, end, price);
   else
     {
      ObjectMove(0, name, 0, start, price);
      ObjectMove(0, name, 1, end, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  }

//+------------------------------------------------------------------+
//| While the range is still building, draw a live preview of it,   |
//| refreshed at most once per new M1 bar to keep this cheap.        |
//+------------------------------------------------------------------+
void UpdateLiveRangeDrawing()
  {
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_lastM1BarTime)
      return;
   g_lastM1BarTime = barTime;

   double hi, lo;
   if(!CalcRangeHighLow(g_rangeStart, TimeCurrent(), hi, lo))
      return;
   if(hi <= 0 || lo <= 0 || hi < lo)
      return;

   DrawRange(g_rangeStart, g_rangeEnd, hi, lo);
  }
//+------------------------------------------------------------------+
