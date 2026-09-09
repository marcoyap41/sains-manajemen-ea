//+------------------------------------------------------------------+
//|                                       NinjaTurtleScalperEA.mq5   |
//|        "Ninja Turtle Scalper" - Donchian Channel breakout EA      |
//|                                                                    |
//| Strategy logic (from the transcript):                             |
//|  - Donchian Channel (highest high / lowest low over N bars, with  |
//|    a middle line) computed on a configurable symbol/timeframe.    |
//|  - Entry trigger, selectable:                                     |
//|      TICK            - buy/sell the instant price touches the     |
//|                         upper/lower channel line                  |
//|      M1_CLOSE         - buy/sell when a M1 candle CLOSES beyond    |
//|                         the channel line                          |
//|      DONCHIAN_CLOSE   - buy/sell when a bar of the Donchian's own  |
//|                         timeframe closes beyond the channel        |
//|                         (channel for this check excludes the bar   |
//|                         being tested, to avoid self-reference)     |
//|  - Re-arm rule: after a SELL signal, another SELL cannot fire      |
//|    until price trades back ABOVE the middle line; after a BUY      |
//|    signal, another BUY cannot fire until price trades back BELOW   |
//|    the middle line. This state is persisted via terminal global    |
//|    variables so it survives an MT5/EA restart.                     |
//|  - Position sizing: fixed lots, OR "money" mode where the lot size |
//|    is calculated so that hitting the initial stop loss would lose  |
//|    approximately the configured money amount.                      |
//|  - Stop loss is mandatory (% of entry price); take profit is       |
//|    optional (% of entry price, 0 = disabled).                      |
//|  - Trailing stop loss: once price has moved TriggerPercent in      |
//|    favor of the position, the SL is trailed at DistancePercent     |
//|    behind the current market price, only modified when the new     |
//|    SL improves on the old one by at least StepPercent.             |
//|  - Only one position open at a time (this EA does not hedge        |
//|    itself against its own trades).                                 |
//|                                                                    |
//| Safety / robustness:                                              |
//|  - Own adjustable magic number; only opens/modifies/closes         |
//|    positions carrying it.                                          |
//|  - Full state (open position, re-arm flags) is rebuilt on OnInit() |
//|    from live position data and persisted terminal global           |
//|    variables, so an MT5/EA restart cannot cause duplicate entries  |
//|    or lost trailing-stop state.                                    |
//|  - Works on any symbol; sizing uses the symbol's own tick size,    |
//|    tick value and volume step, with a margin safety check.         |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//================================= ENUMS ====================================
enum ENUM_VOLUME_MODE
  {
   VOLUME_MODE_LOTS = 0,   // Fixed lot size
   VOLUME_MODE_MONEY = 1   // Risk a fixed money amount (lot size derived from SL distance)
  };

enum ENUM_TRIGGER_MODE
  {
   TRIGGER_TICK = 0,           // Enter the instant price touches the channel line
   TRIGGER_M1_CLOSE = 1,       // Enter when a M1 candle closes beyond the channel line
   TRIGGER_DONCHIAN_CLOSE = 2  // Enter when a Donchian-timeframe bar closes beyond the channel
  };

//================================= INPUTS ===================================
input group "=== General ==="
input ulong             InpMagicNumber       = 20260911;      // Magic number (unique to this EA)
input string            InpComment           = "NinjaTurtleScalper"; // Trade comment
input bool               InpSendLogs          = true;           // Print detailed log messages
input ulong              InpDeviationPoints   = 20;              // Max allowed slippage, in points

input group "=== Volume / position sizing ==="
input ENUM_VOLUME_MODE  InpVolumeMode        = VOLUME_MODE_LOTS; // Lots or Money mode
input double             InpVolume            = 0.10;            // Lots (Lots mode) or money to risk (Money mode)
input int                InpLotDigits         = 2;               // Digits used to round the calculated lot size

input group "=== TP / SL (percent of entry price) ==="
input double             InpTakeProfitPercent = 0.0;             // 0 = no take profit
input double             InpStopLossPercent   = 1.0;              // Required, must be > 0

input group "=== Trailing stop loss ==="
input double             InpTSLTriggerPercent = 0.5;   // Profit % (from entry) that activates trailing; 0 = disabled
input double             InpTSLDistancePercent = 0.1;  // Trailing distance, % of current market price
input double             InpTSLStepPercent    = 0.05;  // Minimum improvement, % of current price, before SL is modified

input group "=== Donchian Channel ==="
input ENUM_TIMEFRAMES   InpDonchianTimeframe = PERIOD_H1;   // Timeframe the channel is calculated on
input int                InpDonchianPeriod    = 20;          // Number of bars used for highest/lowest
input ENUM_TRIGGER_MODE InpTriggerMode       = TRIGGER_TICK; // Entry trigger mode

//================================= GLOBALS ===================================
CTrade   g_trade;
ulong    g_positionTicket   = 0;
int      g_positionDir      = 0;      // +1 = long, -1 = short, 0 = flat

double   g_upper            = 0.0;    // standard channel (for TICK / M1_CLOSE triggers)
double   g_lower            = 0.0;
double   g_middle           = 0.0;
datetime g_lastDonchianBar   = 0;

datetime g_lastM1Bar         = 0;

bool     g_buyArmed         = true;
bool     g_sellArmed        = true;

bool     g_ready            = false;
string   g_gvPrefix         = "";     // prefix for persisted terminal global variables

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   if(InpStopLossPercent <= 0.0)
     {
      Print("NinjaTurtleScalperEA: InpStopLossPercent must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpVolume <= 0.0)
     {
      Print("NinjaTurtleScalperEA: InpVolume must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpDonchianPeriod < 2)
     {
      Print("NinjaTurtleScalperEA: InpDonchianPeriod must be >= 2.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_gvPrefix = "NTS_" + _Symbol + "_" + (string)InpMagicNumber + "_";

   RestoreState();

   // Prime the channel so it is valid before the first new-bar event
   RecomputeStandardChannel();

   g_ready = true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Persist re-arm state so it survives a restart
   GlobalVariableSet(g_gvPrefix + "buyArmed",  g_buyArmed  ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "sellArmed", g_sellArmed ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| Rebuild EA state from live positions + persisted global variables|
//+------------------------------------------------------------------+
void RestoreState()
  {
   g_positionTicket = 0;
   g_positionDir     = 0;

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
         g_positionDir     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         break; // this EA only ever holds one position at a time
        }
     }

   g_buyArmed  = GlobalVariableCheck(g_gvPrefix + "buyArmed")  ? (GlobalVariableGet(g_gvPrefix + "buyArmed")  != 0.0) : true;
   g_sellArmed = GlobalVariableCheck(g_gvPrefix + "sellArmed") ? (GlobalVariableGet(g_gvPrefix + "sellArmed") != 0.0) : true;
  }

//+------------------------------------------------------------------+
//| Standard channel: highest/lowest of the last N COMPLETED bars    |
//| (shift 1..Period). Used for TICK and M1_CLOSE triggers.          |
//+------------------------------------------------------------------+
void RecomputeStandardChannel()
  {
   int idxHigh = iHighest(_Symbol, InpDonchianTimeframe, MODE_HIGH, InpDonchianPeriod, 1);
   int idxLow  = iLowest(_Symbol, InpDonchianTimeframe, MODE_LOW, InpDonchianPeriod, 1);
   if(idxHigh < 0 || idxLow < 0)
      return; // not enough history yet

   g_upper  = iHigh(_Symbol, InpDonchianTimeframe, idxHigh);
   g_lower  = iLow(_Symbol, InpDonchianTimeframe, idxLow);
   g_middle = (g_upper + g_lower) / 2.0;
  }

//+------------------------------------------------------------------+
//| Channel excluding the just-closed bar (shift 2..Period+1),        |
//| used only to evaluate the DONCHIAN_CLOSE trigger without          |
//| self-referencing the bar being tested.                           |
//+------------------------------------------------------------------+
void GetChannelExcludingLastClosed(double &upper, double &lower)
  {
   int idxHigh = iHighest(_Symbol, InpDonchianTimeframe, MODE_HIGH, InpDonchianPeriod, 2);
   int idxLow  = iLowest(_Symbol, InpDonchianTimeframe, MODE_LOW, InpDonchianPeriod, 2);
   upper = (idxHigh >= 0) ? iHigh(_Symbol, InpDonchianTimeframe, idxHigh) : 0.0;
   lower = (idxLow  >= 0) ? iLow(_Symbol, InpDonchianTimeframe, idxLow)   : 0.0;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_ready)
      return;

   // Make sure our tracked position is still alive (may have hit SL/TP, or been closed manually)
   if(g_positionTicket != 0 && !PositionSelectByTicket(g_positionTicket))
     {
      g_positionTicket = 0;
      g_positionDir     = 0;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   //--- Detect a new Donchian-timeframe bar: recompute the channel, and
   //    optionally fire the DONCHIAN_CLOSE trigger on the bar that just closed.
   datetime donchianBarTime = iTime(_Symbol, InpDonchianTimeframe, 0);
   if(donchianBarTime != 0 && donchianBarTime != g_lastDonchianBar)
     {
      bool firstRun = (g_lastDonchianBar == 0);
      g_lastDonchianBar = donchianBarTime;

      if(!firstRun && InpTriggerMode == TRIGGER_DONCHIAN_CLOSE)
        {
         double exUpper, exLower;
         GetChannelExcludingLastClosed(exUpper, exLower);
         double lastClose = iClose(_Symbol, InpDonchianTimeframe, 1);
         if(exUpper > 0.0 && lastClose >= exUpper)
            TryEnter(1);
         else if(exLower > 0.0 && lastClose <= exLower)
            TryEnter(-1);
        }

      RecomputeStandardChannel();
     }

   //--- Detect a new M1 bar: evaluate the M1_CLOSE trigger against the standard channel
   if(InpTriggerMode == TRIGGER_M1_CLOSE)
     {
      datetime m1BarTime = iTime(_Symbol, PERIOD_M1, 0);
      if(m1BarTime != 0 && m1BarTime != g_lastM1Bar)
        {
         bool firstM1 = (g_lastM1Bar == 0);
         g_lastM1Bar = m1BarTime;

         if(!firstM1 && g_upper > 0.0 && g_lower > 0.0)
           {
            double lastM1Close = iClose(_Symbol, PERIOD_M1, 1);
            if(lastM1Close >= g_upper)
               TryEnter(1);
            else if(lastM1Close <= g_lower)
               TryEnter(-1);
           }
        }
     }

   //--- TICK trigger: evaluate against the standard channel on every tick
   if(InpTriggerMode == TRIGGER_TICK && g_upper > 0.0 && g_lower > 0.0)
     {
      if(ask >= g_upper)
         TryEnter(1);
      else if(bid <= g_lower)
         TryEnter(-1);
     }

   //--- Re-arm state: continuously track price crossing the middle line
   UpdateReArmState(bid);

   //--- Manage the trailing stop loss for an open position
   if(g_positionTicket != 0)
      ManageTrailingStop(bid, ask);
  }

//+------------------------------------------------------------------+
//| Update the re-arm flags based on price crossing the middle line  |
//+------------------------------------------------------------------+
void UpdateReArmState(const double bid)
  {
   if(g_middle <= 0.0)
      return;

   if(!g_sellArmed && bid > g_middle)
      g_sellArmed = true;

   if(!g_buyArmed && bid < g_middle)
      g_buyArmed = true;
  }

//+------------------------------------------------------------------+
//| Attempt to enter in the given direction (+1 buy, -1 sell)        |
//+------------------------------------------------------------------+
void TryEnter(const int direction)
  {
   if(g_positionTicket != 0)
      return; // only one position at a time

   if(direction > 0 && !g_buyArmed)
      return;
   if(direction < 0 && !g_sellArmed)
      return;

   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lots  = CalculateLotSize(price);
   if(lots <= 0.0)
     {
      if(InpSendLogs)
         Print("NinjaTurtleScalperEA: calculated lot size invalid, entry skipped.");
      return;
     }

   double sl = (direction > 0)
               ? NormalizeDouble(price * (1.0 - InpStopLossPercent / 100.0), _Digits)
               : NormalizeDouble(price * (1.0 + InpStopLossPercent / 100.0), _Digits);

   double tp = 0.0;
   if(InpTakeProfitPercent > 0.0)
     {
      tp = (direction > 0)
           ? NormalizeDouble(price * (1.0 + InpTakeProfitPercent / 100.0), _Digits)
           : NormalizeDouble(price * (1.0 - InpTakeProfitPercent / 100.0), _Digits);
     }

   bool sent = (direction > 0)
               ? g_trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
               : g_trade.Sell(lots, _Symbol, price, sl, tp, InpComment);

   if(sent)
     {
      ulong ticket = FindOwnPositionTicket();
      if(ticket != 0)
        {
         g_positionTicket = ticket;
         g_positionDir     = direction;
        }
      else if(InpSendLogs)
         Print("NinjaTurtleScalperEA: order sent but position ticket could not be resolved.");

      if(direction > 0)
        {
         g_buyArmed = false;
         GlobalVariableSet(g_gvPrefix + "buyArmed", 0.0);
        }
      else
        {
         g_sellArmed = false;
         GlobalVariableSet(g_gvPrefix + "sellArmed", 0.0);
        }

      if(InpSendLogs)
         Print("NinjaTurtleScalperEA: opened ", (direction > 0 ? "BUY" : "SELL"),
               " ", lots, " lots at ", price, " SL=", sl, " TP=", tp);
     }
   else if(InpSendLogs)
     {
      Print("NinjaTurtleScalperEA: ", (direction > 0 ? "Buy" : "Sell"), "() failed. Retcode ",
            g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
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
//| Position sizing: fixed lots, or money-risk based on SL distance  |
//+------------------------------------------------------------------+
double CalculateLotSize(const double entryPrice)
  {
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(volStep <= 0.0)
     {
      if(InpSendLogs)
         Print("NinjaTurtleScalperEA: invalid symbol volume step.");
      return(0.0);
     }

   double lots;

   if(InpVolumeMode == VOLUME_MODE_LOTS)
     {
      lots = InpVolume;
     }
   else // VOLUME_MODE_MONEY
     {
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0 || entryPrice <= 0.0)
        {
         if(InpSendLogs)
            Print("NinjaTurtleScalperEA: invalid symbol trade parameters, cannot size position.");
         return(0.0);
        }

      double slDistance = entryPrice * InpStopLossPercent / 100.0;
      double lossPerLot = (slDistance / tickSize) * tickValue;
      if(lossPerLot <= 0.0)
         return(0.0);

      lots = InpVolume / lossPerLot; // InpVolume = money to risk in Money mode
     }

   lots = MathFloor(lots / volStep) * volStep;
   lots = NormalizeDouble(lots, InpLotDigits);

   if(lots < volMin)
      lots = volMin;
   if(lots > volMax)
      lots = volMax;

   // Safety check: cap the size if the account cannot actually margin it
   double marginRequired = 0.0;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
   if(OrderCalcMargin(orderType, _Symbol, lots, entryPrice, marginRequired))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired > freeMargin && marginRequired > 0.0)
        {
         double scale = freeMargin / marginRequired;
         lots = MathFloor((lots * scale) / volStep) * volStep;
         lots = NormalizeDouble(lots, InpLotDigits);
         if(InpSendLogs)
            Print("NinjaTurtleScalperEA: lot size reduced to ", lots, " due to insufficient free margin.");
        }
     }

   if(lots < volMin)
      lots = 0.0;

   return(lots);
  }

//+------------------------------------------------------------------+
//| Trail the stop loss once the position is far enough in profit    |
//+------------------------------------------------------------------+
void ManageTrailingStop(const double bid, const double ask)
  {
   if(InpTSLTriggerPercent <= 0.0)
      return; // trailing disabled

   if(!PositionSelectByTicket(g_positionTicket))
      return;

   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL       = PositionGetDouble(POSITION_SL);
   double curTP       = PositionGetDouble(POSITION_TP);
   long   type        = PositionGetInteger(POSITION_TYPE);

   if(type == POSITION_TYPE_BUY)
     {
      double triggerPrice = entryPrice * (1.0 + InpTSLTriggerPercent / 100.0);
      if(bid < triggerPrice)
         return;

      double newSL = NormalizeDouble(bid * (1.0 - InpTSLDistancePercent / 100.0), _Digits);
      double minImprovement = bid * InpTSLStepPercent / 100.0;

      if(newSL > entryPrice && (curSL <= 0.0 || newSL - curSL >= minImprovement))
        {
         if(g_trade.PositionModify(g_positionTicket, newSL, curTP))
           {
            if(InpSendLogs)
               Print("NinjaTurtleScalperEA: trailing SL moved to ", newSL, " for ticket ", g_positionTicket);
           }
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      double triggerPrice = entryPrice * (1.0 - InpTSLTriggerPercent / 100.0);
      if(ask > triggerPrice)
         return;

      double newSL = NormalizeDouble(ask * (1.0 + InpTSLDistancePercent / 100.0), _Digits);
      double minImprovement = ask * InpTSLStepPercent / 100.0;

      if(newSL < entryPrice && (curSL <= 0.0 || curSL - newSL >= minImprovement))
        {
         if(g_trade.PositionModify(g_positionTicket, newSL, curTP))
           {
            if(InpSendLogs)
               Print("NinjaTurtleScalperEA: trailing SL moved to ", newSL, " for ticket ", g_positionTicket);
           }
        }
     }
  }
//+------------------------------------------------------------------+
