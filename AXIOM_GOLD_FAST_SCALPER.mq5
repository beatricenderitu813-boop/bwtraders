//+------------------------------------------------------------------+
//|             AXIOM GOLD FAST SCALPER v1.20                       |
//|             Fast M1 Gold Scalping EA                            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input bool   StartTradingOnAttach      = false;
input long   MagicNumber               = 26092027;
input int    SlippagePoints            = 20;

input ENUM_TIMEFRAMES SignalTimeframe  = PERIOD_M1;

//--- Signal engine
input int    FastEMA                   = 9;
input int    SlowEMA                   = 21;
input int    RSIPeriod                 = 14;

input double BuyRSILevel               = 52.0;
input double SellRSILevel              = 48.0;
input double MinimumSignalScore        = 70.0;

//--- Progressive entries
input double StartingLot               = 0.01;
input double LotMultiplier             = 2.0;

input int    MaximumOpenPositions      = 6;
input double MaximumTotalLots          = 0.64;

input int    AddDistancePoints         = 300;
input bool   RequireSignalForAdd       = true;

//--- Basket protection
input double BasketProfitTarget        = 2.00;
input double BasketProfitRetrace       = 0.50;
input bool   UseProfitRetrace          = true;

//--- Per-trade emergency protection
input double MaximumRiskPercentPerTrade = 0.50;

//--- Account emergency protection
input double MaximumDrawdownPercent    = 5.0;
input int    MaximumConsecutiveLosses  = 3;

//--- Expert logging
input int    StatusIntervalSeconds     = 3;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

int FastEMAHandle = INVALID_HANDLE;
int SlowEMAHandle = INVALID_HANDLE;
int RSIHandle     = INVALID_HANDLE;

bool TradingEnabled = false;

double DayStartBalance = 0.0;

double BasketPeakProfit = 0.0;
bool BasketPeakActive = false;

int ConsecutiveLosses = 0;

datetime LastStatusTime = 0;
datetime LastTickLogTime = 0;

//==================================================================
// FUNCTION DECLARATIONS
//==================================================================

void CreateControlButtons();
void DeleteControlButtons();

void CheckAccountProtection();
void CheckTradingSignals();

int  GetMarketDirection();
double GetBuyScore();
double GetSellScore();

bool CheckFirstEntry();
bool CheckAdditionalEntry();

double CalculateNextLot(int level);
double NormalizeLot(double lot);

int CountEAOpenPositions();
double GetEAOpenLots();

ulong GetNewestPositionTicket();
double GetNewestPositionPrice();

bool OpenProgressiveTrade(int direction);

double CalculateRiskMoney();
bool CalculateSafeStopLoss(
   ENUM_ORDER_TYPE orderType,
   double volume,
   double &stopLoss
);

double GetMinimumStopDistance();

void ManageBasket();
void CloseProfitableBasket();

void LogExpertStatus();
void LogEntryBlockReason(string reason);

void CheckConsecutiveLossProtection();

void CheckNewTradingDay();

bool IsOurPosition(ulong ticket);

double GetBasketProfit();

//==================================================================
// ON INIT
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetAsyncMode(false);

   FastEMAHandle = iMA(
      _Symbol,
      SignalTimeframe,
      FastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   SlowEMAHandle = iMA(
      _Symbol,
      SignalTimeframe,
      SlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   RSIHandle = iRSI(
      _Symbol,
      SignalTimeframe,
      RSIPeriod,
      PRICE_CLOSE
   );

   if(FastEMAHandle == INVALID_HANDLE ||
      SlowEMAHandle == INVALID_HANDLE ||
      RSIHandle == INVALID_HANDLE)
   {
      Print("AXIOM ERROR: Indicator handle creation failed.");
      return(INIT_FAILED);
   }

   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   CreateControlButtons();

   TradingEnabled = StartTradingOnAttach;

   Print("==================================================");
   Print("AXIOM GOLD FAST SCALPER v1.20 INITIALIZED");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: M1");
   Print("Daily loss protection: REMOVED");
   Print("Manual daily loss control: ENABLED");
   Print("Maximum drawdown: ", MaximumDrawdownPercent, "%");
   Print("Maximum consecutive losses: ",
         MaximumConsecutiveLosses);
   Print("Risk per trade: ",
         MaximumRiskPercentPerTrade, "%");
   Print("Trading state: ",
         TradingEnabled ? "STARTED" : "STOPPED");
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// ON DEINIT
//==================================================================

void OnDeinit(const int reason)
{
   if(FastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(FastEMAHandle);

   if(SlowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(SlowEMAHandle);

   if(RSIHandle != INVALID_HANDLE)
      IndicatorRelease(RSIHandle);

   DeleteControlButtons();

   Print("AXIOM stopped. Reason: ", reason);
}

//==================================================================
// ON TICK
//==================================================================

void OnTick()
{
   CheckNewTradingDay();

   // Always manage open positions
   ManageBasket();

   // Emergency account protection
   CheckAccountProtection();

   // Consecutive loss protection
   CheckConsecutiveLossProtection();

   // Display progress
   LogExpertStatus();

   // STOP means no new entries
   if(!TradingEnabled)
      return;

   // Check for first/additional trade immediately
   CheckTradingSignals();
}

//==================================================================
// NEW TRADING DAY
//==================================================================

void CheckNewTradingDay()
{
   static int storedDay = -1;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   if(storedDay == -1)
   {
      storedDay = tm.day;
      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return;
   }

   if(tm.day != storedDay)
   {
      storedDay = tm.day;

      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      ConsecutiveLosses = 0;

      BasketPeakProfit = 0.0;
      BasketPeakActive = false;

      Print("AXIOM: New trading day detected.");
      Print("AXIOM: New day starting balance = ",
            DoubleToString(DayStartBalance,2));
   }
}

//==================================================================
// ACCOUNT PROTECTION
//==================================================================

void CheckAccountProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(DayStartBalance <= 0.0)
      return;

   double drawdown =
      ((DayStartBalance - equity) / DayStartBalance) * 100.0;

   if(drawdown >= MaximumDrawdownPercent)
   {
      if(TradingEnabled)
      {
         TradingEnabled = false;

         Print("AXIOM EMERGENCY PROTECTION");
         Print("Drawdown = ",
               DoubleToString(drawdown,2),
               "%");
         Print("New entries BLOCKED.");
         Print("Existing positions remain under basket management.");
      }
   }
}

//==================================================================
// CONSECUTIVE LOSS PROTECTION
//==================================================================

void CheckConsecutiveLossProtection()
{
   if(MaximumConsecutiveLosses <= 0)
      return;

   if(ConsecutiveLosses >= MaximumConsecutiveLosses)
   {
      if(TradingEnabled)
      {
         TradingEnabled = false;

         Print("AXIOM: Maximum consecutive losses reached.");
         Print("Loss streak = ", ConsecutiveLosses);
         Print("New entries BLOCKED.");
      }
   }
}

//==================================================================
// CONTROL BUTTONS
//==================================================================

void CreateControlButtons()
{
   ObjectCreate(
      0,
      "AXIOM_START",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "AXIOM_START",
      OBJPROP_XDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "AXIOM_START",
      OBJPROP_YDISTANCE,
      30
   );

   ObjectSetInteger(
      0,
      "AXIOM_START",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "AXIOM_START",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "AXIOM_START",
      OBJPROP_TEXT,
      "START"
   );

   ObjectCreate(
      0,
      "AXIOM_STOP",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "AXIOM_STOP",
      OBJPROP_XDISTANCE,
      130
   );

   ObjectSetInteger(
      0,
      "AXIOM_STOP",
      OBJPROP_YDISTANCE,
      30
   );

   ObjectSetInteger(
      0,
      "AXIOM_STOP",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "AXIOM_STOP",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "AXIOM_STOP",
      OBJPROP_TEXT,
      "STOP"
   );

   ChartRedraw();
}

//==================================================================
// DELETE BUTTONS
//==================================================================

void DeleteControlButtons()
{
   ObjectDelete(0,"AXIOM_START");
   ObjectDelete(0,"AXIOM_STOP");
}

//==================================================================
// CHART EVENTS
//==================================================================

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "AXIOM_START")
   {
      TradingEnabled = true;

      Print("AXIOM START pressed.");
      Print("New entries are ENABLED.");
   }

   if(sparam == "AXIOM_STOP")
   {
      TradingEnabled = false;

      Print("AXIOM STOP pressed.");
      Print("New entries are DISABLED.");
      Print("Existing positions remain under protection.");
   }
}//==================================================================
// MARKET DIRECTION
//==================================================================

int GetMarketDirection()
{
   double fast[1];
   double slow[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fast) != 1)
      return 0;

   if(CopyBuffer(SlowEMAHandle,0,0,1,slow) != 1)
      return 0;

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return 0;

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double mid = (bid + ask) / 2.0;

   if(fast[0] > slow[0] &&
      mid > fast[0] &&
      rsi[0] >= BuyRSILevel)
   {
      return 1;
   }

   if(fast[0] < slow[0] &&
      mid < fast[0] &&
      rsi[0] <= SellRSILevel)
   {
      return -1;
   }

   return 0;
}

//==================================================================
// BUY SCORE
//==================================================================

double GetBuyScore()
{
   double score = 0.0;

   double fast[1];
   double slow[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fast) != 1)
      return 0.0;

   if(CopyBuffer(SlowEMAHandle,0,0,1,slow) != 1)
      return 0.0;

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return 0.0;

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double mid = (bid + ask) / 2.0;

   // EMA trend
   if(fast[0] > slow[0])
      score += 35.0;

   // Price above fast EMA
   if(mid > fast[0])
      score += 20.0;

   // RSI confirmation
   if(rsi[0] >= BuyRSILevel)
      score += 30.0;

   // Current forming candle momentum
   double open0 = iOpen(
      _Symbol,
      SignalTimeframe,
      0
   );

   double close0 = iClose(
      _Symbol,
      SignalTimeframe,
      0
   );

   if(close0 > open0)
      score += 15.0;

   return score;
}

//==================================================================
// SELL SCORE
//==================================================================

double GetSellScore()
{
   double score = 0.0;

   double fast[1];
   double slow[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fast) != 1)
      return 0.0;

   if(CopyBuffer(SlowEMAHandle,0,0,1,slow) != 1)
      return 0.0;

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return 0.0;

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double mid = (bid + ask) / 2.0;

   // EMA trend
   if(fast[0] < slow[0])
      score += 35.0;

   // Price below fast EMA
   if(mid < fast[0])
      score += 20.0;

   // RSI confirmation
   if(rsi[0] <= SellRSILevel)
      score += 30.0;

   // Current forming candle momentum
   double open0 = iOpen(
      _Symbol,
      SignalTimeframe,
      0
   );

   double close0 = iClose(
      _Symbol,
      SignalTimeframe,
      0
   );

   if(close0 < open0)
      score += 15.0;

   return score;
}

//==================================================================
// CHECK SIGNALS
//==================================================================

void CheckTradingSignals()
{
   int positions = CountEAOpenPositions();

   if(positions <= 0)
   {
      CheckFirstEntry();
      return;
   }

   CheckAdditionalEntry();
}

//==================================================================
// FIRST ENTRY
//==================================================================

bool CheckFirstEntry()
{
   double buyScore = GetBuyScore();
   double sellScore = GetSellScore();

   if(buyScore < MinimumSignalScore &&
      sellScore < MinimumSignalScore)
   {
      return false;
   }

   if(buyScore > sellScore &&
      buyScore >= MinimumSignalScore)
   {
      Print("AXIOM SIGNAL: BUY");
      Print("BUY score = ",
            DoubleToString(buyScore,1),
            "%");

      return OpenProgressiveTrade(1);
   }

   if(sellScore > buyScore &&
      sellScore >= MinimumSignalScore)
   {
      Print("AXIOM SIGNAL: SELL");
      Print("SELL score = ",
            DoubleToString(sellScore,1),
            "%");

      return OpenProgressiveTrade(-1);
   }

   return false;
}

//==================================================================
// ADDITIONAL ENTRY
//==================================================================

bool CheckAdditionalEntry()
{
   int count = CountEAOpenPositions();

   if(count >= MaximumOpenPositions)
   {
      LogEntryBlockReason(
         "Maximum open positions reached"
      );

      return false;
   }

   double totalLots = GetEAOpenLots();

   if(totalLots >= MaximumTotalLots)
   {
      LogEntryBlockReason(
         "Maximum total lots reached"
      );

      return false;
   }

   ulong newestTicket = GetNewestPositionTicket();

   if(newestTicket == 0)
      return false;

   if(!PositionSelectByTicket(newestTicket))
      return false;

   ENUM_POSITION_TYPE newestType =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   double newestPrice =
      PositionGetDouble(POSITION_PRICE_OPEN);

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double point = SymbolInfoDouble(
      _Symbol,
      SYMBOL_POINT
   );

   if(point <= 0.0)
      return false;

   double distancePoints = 0.0;

   if(newestType == POSITION_TYPE_BUY)
   {
      distancePoints =
         (newestPrice - bid) / point;
   }
   else
   {
      distancePoints =
         (ask - newestPrice) / point;
   }

   // Do not add before required distance
   if(distancePoints < AddDistancePoints)
      return false;

   double buyScore = GetBuyScore();
   double sellScore = GetSellScore();

   // BUY basket
   if(newestType == POSITION_TYPE_BUY)
   {
      if(RequireSignalForAdd)
      {
         if(buyScore < MinimumSignalScore ||
            buyScore <= sellScore)
         {
            LogEntryBlockReason(
               "BUY add waiting for live confirmation"
            );

            return false;
         }
      }

      Print("AXIOM: BUY add distance reached.");
      Print("Distance = ",
            DoubleToString(distancePoints,0),
            " points");

      return OpenProgressiveTrade(1);
   }

   // SELL basket
   if(newestType == POSITION_TYPE_SELL)
   {
      if(RequireSignalForAdd)
      {
         if(sellScore < MinimumSignalScore ||
            sellScore <= buyScore)
         {
            LogEntryBlockReason(
               "SELL add waiting for live confirmation"
            );

            return false;
         }
      }

      Print("AXIOM: SELL add distance reached.");
      Print("Distance = ",
            DoubleToString(distancePoints,0),
            " points");

      return OpenProgressiveTrade(-1);
   }

   return false;
}

//==================================================================
// LOT CALCULATION
//==================================================================

double CalculateNextLot(int level)
{
   double lot =
      StartingLot *
      MathPow(LotMultiplier, level);

   return NormalizeLot(lot);
}

//==================================================================
// NORMALIZE LOT
//==================================================================

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MIN
   );

   double maxLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MAX
   );

   double step = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_STEP
   );

   if(step <= 0.0)
      step = 0.01;

   if(lot < minLot)
      lot = minLot;

   if(lot > maxLot)
      lot = maxLot;

   lot = MathFloor(lot / step) * step;

   int digits = 2;

   if(step >= 1.0)
      digits = 0;
   else if(step >= 0.1)
      digits = 1;
   else
      digits = 2;

   return NormalizeDouble(lot,digits);
}

//==================================================================
// COUNT EA POSITIONS
//==================================================================

int CountEAOpenPositions()
{
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
         POSITION_MAGIC) != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//==================================================================
// TOTAL EA LOTS
//==================================================================

double GetEAOpenLots()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
         POSITION_MAGIC) != MagicNumber)
         continue;

      total += PositionGetDouble(
         POSITION_VOLUME);
   }

   return total;
}

//==================================================================
// NEWEST POSITION
//==================================================================

ulong GetNewestPositionTicket()
{
   ulong newestTicket = 0;
   long newestTime = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
         POSITION_MAGIC) != MagicNumber)
         continue;

      long timeValue =
         (long)PositionGetInteger(
            POSITION_TIME_MSC);

      if(timeValue > newestTime)
      {
         newestTime = timeValue;
         newestTicket = ticket;
      }
   }

   return newestTicket;
}

//==================================================================
// NEWEST POSITION PRICE
//==================================================================

double GetNewestPositionPrice()
{
   ulong ticket = GetNewestPositionTicket();

   if(ticket == 0)
      return 0.0;

   if(!PositionSelectByTicket(ticket))
      return 0.0;

   return PositionGetDouble(
      POSITION_PRICE_OPEN);
}

//==================================================================
// CALCULATE RISK MONEY
//==================================================================

double CalculateRiskMoney()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   return balance *
          MaximumRiskPercentPerTrade /
          100.0;
}

//==================================================================
// MINIMUM STOP DISTANCE
//==================================================================

double GetMinimumStopDistance()
{
   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT);

   if(point <= 0.0)
      return 0.0;

   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL);

   long freezeLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_FREEZE_LEVEL);

   long required =
      MathMax(stopsLevel,freezeLevel);

   required += 10;

   return required * point;
}//==================================================================
// SAFE STOP LOSS CALCULATION
//==================================================================

bool CalculateSafeStopLoss(
   ENUM_ORDER_TYPE orderType,
   double volume,
   double &stopLoss
)
{
   if(volume <= 0.0)
      return false;

   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE);

   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT);

   if(tickSize <= 0.0 ||
      tickValue <= 0.0 ||
      point <= 0.0)
   {
      Print("AXIOM: Cannot calculate safe SL.");
      return false;
   }

   double riskMoney =
      CalculateRiskMoney();

   if(riskMoney <= 0.0)
      return false;

   double priceDistance =
      (riskMoney * tickSize) /
      (volume * tickValue);

   double minimumDistance =
      GetMinimumStopDistance();

   // Broker minimum stop distance is enforced
   if(priceDistance < minimumDistance)
      priceDistance = minimumDistance;

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   int digits =
      (int)SymbolInfoInteger(
         _Symbol,
         SYMBOL_DIGITS);

   if(orderType == ORDER_TYPE_BUY)
   {
      if(bid <= 0.0)
         return false;

      stopLoss =
         NormalizeDouble(
            bid - priceDistance,
            digits);

      if(stopLoss <= 0.0)
         return false;

      if((bid - stopLoss) < minimumDistance)
         return false;
   }
   else
   {
      if(ask <= 0.0)
         return false;

      stopLoss =
         NormalizeDouble(
            ask + priceDistance,
            digits);

      if(stopLoss <= 0.0)
         return false;

      if((stopLoss - ask) < minimumDistance)
         return false;
   }

   return true;
}

//==================================================================
// OPEN PROGRESSIVE TRADE
//==================================================================

bool OpenProgressiveTrade(int direction)
{
   int level = CountEAOpenPositions();

   if(level >= MaximumOpenPositions)
      return false;

   double totalLots = GetEAOpenLots();

   double lot =
      CalculateNextLot(level);

   if(totalLots + lot > MaximumTotalLots)
   {
      Print("AXIOM: Total lot limit would be exceeded.");
      Print("Current lots = ",
            DoubleToString(totalLots,2));
      Print("New lot = ",
            DoubleToString(lot,2));

      return false;
   }

   double stopLoss = 0.0;

   ENUM_ORDER_TYPE orderType;

   if(direction > 0)
      orderType = ORDER_TYPE_BUY;
   else
      orderType = ORDER_TYPE_SELL;

   if(!CalculateSafeStopLoss(
         orderType,
         lot,
         stopLoss))
   {
      Print("AXIOM: Safe SL calculation failed.");
      return false;
   }

   bool result = false;

   string comment =
      "AXIOM LEVEL " +
      IntegerToString(level + 1);

   if(direction > 0)
   {
      result =
         trade.Buy(
            lot,
            _Symbol,
            0.0,
            stopLoss,
            0.0,
            comment);
   }
   else
   {
      result =
         trade.Sell(
            lot,
            _Symbol,
            0.0,
            stopLoss,
            0.0,
            comment);
   }

   if(result)
   {
      Print("==================================================");

      if(direction > 0)
         Print("AXIOM FAST BUY EXECUTED");
      else
         Print("AXIOM FAST SELL EXECUTED");

      Print("Level: ",level + 1);
      Print("Lot: ",
            DoubleToString(lot,2));
      Print("SL: ",
            DoubleToString(stopLoss,
               (int)SymbolInfoInteger(
                  _Symbol,
                  SYMBOL_DIGITS)));

      Print("Current positions: ",
            CountEAOpenPositions());

      Print("Total lots: ",
            DoubleToString(
               GetEAOpenLots(),2));

      Print("==================================================");

      return true;
   }

   Print("AXIOM TRADE FAILED.");
   Print("Retcode: ",
         trade.ResultRetcode());

   Print("Description: ",
         trade.ResultRetcodeDescription());

   return false;
}

//==================================================================
// BASKET PROFIT
//==================================================================

double GetBasketProfit()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
         POSITION_MAGIC) != MagicNumber)
         continue;

      total += PositionGetDouble(
         POSITION_PROFIT);

      total += PositionGetDouble(
         POSITION_SWAP);
   }

   return total;
}

//==================================================================
// BASKET MANAGEMENT
//==================================================================

void ManageBasket()
{
   int count = CountEAOpenPositions();

   if(count <= 0)
   {
      BasketPeakProfit = 0.0;
      BasketPeakActive = false;
      return;
   }

   double basketProfit =
      GetBasketProfit();

   // Only protect established positive profit
   if(basketProfit > 0.0)
   {
      if(!BasketPeakActive)
      {
         BasketPeakActive = true;
         BasketPeakProfit = basketProfit;

         Print("AXIOM: Basket profit protection activated.");
         Print("Peak = $",
               DoubleToString(
                  BasketPeakProfit,2));
      }

      if(basketProfit > BasketPeakProfit)
      {
         BasketPeakProfit = basketProfit;

         Print("AXIOM: New basket profit peak = $",
               DoubleToString(
                  BasketPeakProfit,2));
      }
   }

   // Basket target
   if(basketProfit >= BasketProfitTarget)
   {
      Print("AXIOM: Basket profit target reached.");
      Print("Basket = $",
            DoubleToString(
               basketProfit,2));

      CloseProfitableBasket();
      return;
   }

   // Profit retracement
   if(UseProfitRetrace &&
      BasketPeakActive &&
      BasketPeakProfit > BasketProfitRetrace)
   {
      double protectionLevel =
         BasketPeakProfit -
         BasketProfitRetrace;

      if(basketProfit <= protectionLevel &&
         basketProfit > 0.0)
      {
         Print("AXIOM: Basket profit retracement triggered.");
         Print("Peak = $",
               DoubleToString(
                  BasketPeakProfit,2));

         Print("Current = $",
               DoubleToString(
                  basketProfit,2));

         CloseProfitableBasket();
      }
   }
}

//==================================================================
// CLOSE PROFITABLE POSITIONS
//==================================================================

void CloseProfitableBasket()
{
   double basketProfit =
      GetBasketProfit();

   // NEVER intentionally close a losing basket
   if(basketProfit <= 0.0)
   {
      Print("AXIOM: Basket is not profitable.");
      Print("No basket closure performed.");
      return;
   }

   bool closedSomething = false;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
         POSITION_MAGIC) != MagicNumber)
         continue;

      double profit =
         PositionGetDouble(
            POSITION_PROFIT);

      // Only close profitable positions
      if(profit > 0.0)
      {
         if(trade.PositionClose(ticket))
         {
            closedSomething = true;

            Print("AXIOM: Profitable position closed.");
            Print("Ticket = ",ticket);
            Print("Profit = $",
                  DoubleToString(
                     profit,2));
         }
      }
   }

   if(closedSomething)
   {
      BasketPeakProfit = 0.0;
      BasketPeakActive = false;

      Print("AXIOM: Profit protection cycle completed.");
   }
}

//==================================================================
// POSITION CHECK
//==================================================================

bool IsOurPosition(ulong ticket)
{
   if(ticket == 0)
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   if(PositionGetString(POSITION_SYMBOL)
      != _Symbol)
      return false;

   if((long)PositionGetInteger(
      POSITION_MAGIC) != MagicNumber)
      return false;

   return true;
}

//==================================================================
// TRADE TRANSACTION
//==================================================================

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;

   if(deal == 0)
      return;

   if(!HistoryDealSelect(deal))
      return;

   string symbol =
      HistoryDealGetString(
         deal,
         DEAL_SYMBOL);

   if(symbol != _Symbol)
      return;

   long magic =
      HistoryDealGetInteger(
         deal,
         DEAL_MAGIC);

   if(magic != MagicNumber)
      return;

   long entry =
      HistoryDealGetInteger(
         deal,
         DEAL_ENTRY);

   if(entry != DEAL_ENTRY_OUT &&
      entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit =
      HistoryDealGetDouble(
         deal,
         DEAL_PROFIT);

   double swap =
      HistoryDealGetDouble(
         deal,
         DEAL_SWAP);

   double commission =
      HistoryDealGetDouble(
         deal,
         DEAL_COMMISSION);

   double net =
      profit +
      swap +
      commission;

   if(net < 0.0)
   {
      ConsecutiveLosses++;

      Print("AXIOM: Losing trade closed.");
      Print("Net loss = $",
            DoubleToString(
               net,2));

      Print("Consecutive losses = ",
            ConsecutiveLosses);
   }
   else if(net > 0.0)
   {
      ConsecutiveLosses = 0;

      Print("AXIOM: Winning trade closed.");
      Print("Net profit = $",
            DoubleToString(
               net,2));

      Print("Loss streak reset.");
   }
}

//==================================================================
// EXPERT STATUS
//==================================================================

void LogExpertStatus()
{
   datetime now = TimeCurrent();

   if(StatusIntervalSeconds > 0)
   {
      if(now - LastStatusTime <
         StatusIntervalSeconds)
         return;
   }

   LastStatusTime = now;

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   double basket =
      GetBasketProfit();

   int direction =
      GetMarketDirection();

   string dirText = "NEUTRAL";

   if(direction > 0)
      dirText = "BUY";

   if(direction < 0)
      dirText = "SELL";

   Print(
      "AXIOM STATUS | ",
      "State=",
      TradingEnabled ? "STARTED" : "STOPPED",
      " | Direction=",
      dirText,
      " | BUY=",
      DoubleToString(buyScore,1),
      "% | SELL=",
      DoubleToString(sellScore,1),
      "% | Positions=",
      CountEAOpenPositions(),
      " | Lots=",
      DoubleToString(
         GetEAOpenLots(),2),
      " | Basket=$",
      DoubleToString(
         basket,2),
      " | LossStreak=",
      ConsecutiveLosses
   );
}

//==================================================================
// ENTRY BLOCK LOG
//==================================================================

void LogEntryBlockReason(string reason)
{
   datetime now = TimeCurrent();

   if(now - LastTickLogTime < 3)
      return;

   LastTickLogTime = now;

   Print("AXIOM ENTRY WAITING: ",
         reason);
}//+------------------------------------------------------------------+
