//+------------------------------------------------------------------+
//|                                                RSI_Trend_EA.mq5   |
//|  RSI-based Expert Advisor with optional MA filter, percentage-   |
//|  based SL/TP, percentage-based trailing stop and risk-based lot  |
//|  sizing. Works on any symbol, keeps its own magic number, and    |
//|  restores its arming state after an MT5/terminal restart.        |
//+------------------------------------------------------------------+
#property copyright "marcoyap41"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Risk mode ---------------------------------------------------------
enum ENUM_RISK_MODE
  {
   RISK_MODE_PERCENT = 0,   // % of account balance
   RISK_MODE_MONEY   = 1    // Fixed money amount
  };

//--- Inputs --------------------------------------------------------------
input group "=== General ==="
input long             InpMagicNumber        = 123456;    // Magic number
input int              InpSlippage           = 30;         // Max slippage (points)
input string           InpTradeComment       = "RSI_EA";   // Trade comment

input group "=== RSI Signal ==="
input int              InpRSIPeriod          = 14;         // RSI period
input ENUM_TIMEFRAMES  InpRSITimeframe       = PERIOD_H1;  // RSI timeframe
input double           InpRSIBuyLevel        = 30.0;       // RSI buy threshold (oversold)
input double           InpRSISellLevel       = 70.0;       // RSI sell threshold (overbought)
input double           InpRSIMidLevel        = 50.0;       // RSI re-arm level

input group "=== Moving Average Filter ==="
input bool             InpUseMAFilter        = false;      // Enable MA filter
input int              InpMAPeriod           = 50;         // MA period
input ENUM_TIMEFRAMES  InpMATimeframe        = PERIOD_D1;  // MA timeframe
input ENUM_MA_METHOD   InpMAMethod           = MODE_SMA;   // MA method

input group "=== Stop Loss / Take Profit (% of open price) ==="
input double           InpStopLossPercent    = 5.0;        // Stop Loss % (0 = disabled)
input double           InpTakeProfitPercent  = 1.0;        // Take Profit % (0 = disabled)

input group "=== Trailing Stop (% of open price) ==="
input double           InpTrailTriggerPercent  = 0.5;      // Trailing trigger % (0 = disabled)
input double           InpTrailDistancePercent = 0.1;      // Trailing distance %
input double           InpTrailStepPercent     = 0.05;     // Trailing step %

input group "=== Risk / Position Sizing ==="
input ENUM_RISK_MODE   InpRiskMode           = RISK_MODE_PERCENT; // Risk mode
input double           InpRiskValue          = 1.0;        // Risk value (% of balance or money)
input double           InpFallbackLots       = 0.01;       // Lot size used when SL is disabled

//--- Globals ---------------------------------------------------------------
CTrade   trade;
int      rsiHandle = INVALID_HANDLE;
int      maHandle  = INVALID_HANDLE;

bool     buyArmed  = true;
bool     sellArmed = true;

datetime lastSignalBarTime = 0;

string   gvBuyArmed  = "";
string   gvSellArmed = "";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRSIPeriod <= 1)
     {
      Print("RSI_EA: invalid RSI period");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpUseMAFilter && InpMAPeriod <= 1)
     {
      Print("RSI_EA: invalid MA period");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpStopLossPercent < 0.0 || InpTakeProfitPercent < 0.0 ||
      InpTrailTriggerPercent < 0.0 || InpTrailDistancePercent < 0.0 || InpTrailStepPercent < 0.0)
     {
      Print("RSI_EA: percentage inputs cannot be negative");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskValue <= 0.0 && InpStopLossPercent > 0.0)
     {
      Print("RSI_EA: risk value must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }

   rsiHandle = iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
     {
      Print("RSI_EA: failed to create RSI handle, error ", GetLastError());
      return(INIT_FAILED);
     }

   if(InpUseMAFilter)
     {
      maHandle = iMA(_Symbol, InpMATimeframe, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(maHandle == INVALID_HANDLE)
        {
         Print("RSI_EA: failed to create MA handle, error ", GetLastError());
         return(INIT_FAILED);
        }
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetFillingType());
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   gvBuyArmed  = "RSI_EA_" + IntegerToString(InpMagicNumber) + "_" + _Symbol + "_BuyArmed";
   gvSellArmed = "RSI_EA_" + IntegerToString(InpMagicNumber) + "_" + _Symbol + "_SellArmed";

   RestoreState();
   lastSignalBarTime = 0;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop();

   if(!IsNewBar())
      return;

   if(BarsCalculated(rsiHandle) < 3)
      return;

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsi) < 2)
      return;

   double rsiClosed = rsi[0]; // last fully closed bar of InpRSITimeframe

   // Re-arm logic: once RSI closes back above/below the mid level,
   // that side becomes eligible to trade again.
   if(rsiClosed > InpRSIMidLevel && !buyArmed)
      SaveBuyArmed(true);
   if(rsiClosed < InpRSIMidLevel && !sellArmed)
      SaveSellArmed(true);

   double maValue = 0.0;
   if(InpUseMAFilter)
     {
      if(BarsCalculated(maHandle) < 2)
         return;
      double ma[];
      ArraySetAsSeries(ma, true);
      if(CopyBuffer(maHandle, 0, 1, 1, ma) < 1)
         return;
      maValue = ma[0];
     }

   if(buyArmed && rsiClosed < InpRSIBuyLevel)
      TryOpenBuy(maValue);

   if(sellArmed && rsiClosed > InpRSISellLevel)
      TryOpenSell(maValue);
  }

//+------------------------------------------------------------------+
//| Detect a new closed bar on the RSI timeframe                     |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t[1];
   if(CopyTime(_Symbol, InpRSITimeframe, 0, 1, t) < 1)
      return false;
   if(t[0] != lastSignalBarTime)
     {
      lastSignalBarTime = t[0];
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Restore armed state after a restart                              |
//+------------------------------------------------------------------+
void RestoreState()
  {
   buyArmed  = GlobalVariableCheck(gvBuyArmed)  ? (GlobalVariableGet(gvBuyArmed)  != 0.0) : true;
   sellArmed = GlobalVariableCheck(gvSellArmed) ? (GlobalVariableGet(gvSellArmed) != 0.0) : true;
  }

void SaveBuyArmed(bool val)
  {
   buyArmed = val;
   GlobalVariableSet(gvBuyArmed, val ? 1.0 : 0.0);
  }

void SaveSellArmed(bool val)
  {
   sellArmed = val;
   GlobalVariableSet(gvSellArmed, val ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| Pick a filling mode supported by the symbol                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingType()
  {
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| Normalize price to the symbol's digits                           |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

//+------------------------------------------------------------------+
//| Enforce the broker's minimum stop distance                       |
//+------------------------------------------------------------------+
double EnforceStopsLevel(double price, double refPrice, bool isAbove)
  {
   long   stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point         = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist        = stopsLevelPts * point;
   if(minDist <= 0.0)
      return price;

   if(isAbove && (price - refPrice) < minDist)
      price = refPrice + minDist;
   else if(!isAbove && (refPrice - price) < minDist)
      price = refPrice - minDist;

   return NormalizePrice(price);
  }

//+------------------------------------------------------------------+
//| Calculate lot size from risk settings                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double openPrice, double slPrice)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lots;

   if(slPrice <= 0.0)
     {
      // No SL defined: risk cannot be derived from a stop distance.
      lots = InpFallbackLots;
     }
   else
     {
      double riskMoney = (InpRiskMode == RISK_MODE_PERCENT)
                          ? AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskValue / 100.0
                          : InpRiskValue;

      double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double slDistance = MathAbs(openPrice - slPrice);

      if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0)
        {
         Print("RSI_EA: cannot derive lot size from risk, using fallback lot size");
         lots = InpFallbackLots;
        }
      else
        {
         double lossPerLot = slDistance / tickSize * tickValue;
         lots = (lossPerLot > 0.0) ? riskMoney / lossPerLot : InpFallbackLots;
        }
     }

   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = NormalizeDouble(lots, 2);

   return lots;
  }

//+------------------------------------------------------------------+
//| Try to open a buy position                                       |
//+------------------------------------------------------------------+
void TryOpenBuy(double maValue)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(InpUseMAFilter && ask <= maValue)
      return;

   double sl = 0.0, tp = 0.0;
   if(InpStopLossPercent > 0.0)
      sl = EnforceStopsLevel(NormalizePrice(ask * (1.0 - InpStopLossPercent / 100.0)), ask, false);
   if(InpTakeProfitPercent > 0.0)
      tp = EnforceStopsLevel(NormalizePrice(ask * (1.0 + InpTakeProfitPercent / 100.0)), ask, true);

   double lots = CalculateLotSize(ask, sl);
   if(lots <= 0.0)
      return;

   if(trade.Buy(lots, _Symbol, ask, sl, tp, InpTradeComment))
      SaveBuyArmed(false);
   else
      Print("RSI_EA: buy order failed, retcode=", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), ")");
  }

//+------------------------------------------------------------------+
//| Try to open a sell position                                      |
//+------------------------------------------------------------------+
void TryOpenSell(double maValue)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpUseMAFilter && bid >= maValue)
      return;

   double sl = 0.0, tp = 0.0;
   if(InpStopLossPercent > 0.0)
      sl = EnforceStopsLevel(NormalizePrice(bid * (1.0 + InpStopLossPercent / 100.0)), bid, true);
   if(InpTakeProfitPercent > 0.0)
      tp = EnforceStopsLevel(NormalizePrice(bid * (1.0 - InpTakeProfitPercent / 100.0)), bid, false);

   double lots = CalculateLotSize(bid, sl);
   if(lots <= 0.0)
      return;

   if(trade.Sell(lots, _Symbol, bid, sl, tp, InpTradeComment))
      SaveSellArmed(false);
   else
      Print("RSI_EA: sell order failed, retcode=", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), ")");
  }

//+------------------------------------------------------------------+
//| Manage the percentage-based trailing stop for own positions      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   if(InpTrailTriggerPercent <= 0.0)
      return;

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

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL      = PositionGetDouble(POSITION_SL);
      double curTP      = PositionGetDouble(POSITION_TP);

      double triggerDist = openPrice * InpTrailTriggerPercent  / 100.0;
      double trailDist    = openPrice * InpTrailDistancePercent / 100.0;
      double stepDist     = openPrice * InpTrailStepPercent     / 100.0;

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - openPrice) < triggerDist)
            continue;

         double newSL = EnforceStopsLevel(NormalizePrice(bid - trailDist), bid, false);
         bool   dueForUpdate = (curSL == 0.0) || ((newSL - curSL) >= stepDist);

         if(dueForUpdate && newSL > curSL)
           {
            if(!trade.PositionModify(ticket, newSL, curTP))
               Print("RSI_EA: trailing SL modify failed (buy) #", ticket, " ", trade.ResultRetcodeDescription());
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((openPrice - ask) < triggerDist)
            continue;

         double newSL = EnforceStopsLevel(NormalizePrice(ask + trailDist), ask, true);
         bool   dueForUpdate = (curSL == 0.0) || ((curSL - newSL) >= stepDist);

         if(dueForUpdate && (curSL == 0.0 || newSL < curSL))
           {
            if(!trade.PositionModify(ticket, newSL, curTP))
               Print("RSI_EA: trailing SL modify failed (sell) #", ticket, " ", trade.ResultRetcodeDescription());
           }
        }
     }
  }
//+------------------------------------------------------------------+
