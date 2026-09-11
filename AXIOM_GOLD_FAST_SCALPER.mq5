//+------------------------------------------------------------------+
//|              AXIOM GOLD FAST SCALPER v1.30                      |
//|              Fast M1 Gold Scalping EA                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input bool   StartTradingOnAttach       = false;
input long   MagicNumber                = 26092027;
input int    SlippagePoints             = 20;

input ENUM_TIMEFRAMES SignalTimeframe   = PERIOD_M1;

//--- Signal engine
input int    FastEMA                    = 9;
input int    SlowEMA                    = 21;
input int    RSIPeriod                  = 14;

input double BuyRSILevel                = 52.0;
input double SellRSILevel               = 48.0;

input double MinimumSignalScore         = 70.0;

//--- Stronger confirmation for additions
input double MinimumAddSignalScore      = 80.0;

//--- Progressive entries
input double StartingLot                = 0.01;
input double LotMultiplier              = 2.0;

input int    MaximumOpenPositions       = 6;
input double MaximumTotalLots           = 0.64;

input int    AddDistancePoints          = 300;
input bool   RequireSignalForAdd        = true;

//--- Basket profit protection
input double BasketProfitTarget         = 2.00;
input double BasketProfitRetrace        = 0.50;
input double BasketProfitRetracePercent = 50.0;

input bool   UseProfitRetrace            = true;

//--- Maximum risk per individual trade
input double MaximumRiskPercentPerTrade = 0.50;

//--- Emergency account protection
input double MaximumDrawdownPercent     = 5.0;

//--- Expert logging
input int    StatusIntervalSeconds      = 3;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

int FastEMAHandle = INVALID_HANDLE;
int SlowEMAHandle = INVALID_HANDLE;
int RSIHandle     = INVALID_HANDLE;

bool TradingEnabled = false;

double DayStartBalance = 0.0;

double BasketPeakProfit = 0.0;
bool   BasketPeakActive = false;

datetime LastStatusTime = 0;
datetime LastBlockLogTime = 0;

//==================================================================
// FUNCTION DECLARATIONS
//==================================================================

void CreateControlButtons();
void DeleteControlButtons();

void CheckAccountProtection();
void CheckTradingSignals();

int    GetMarketDirection();
double GetBuyScore();
double GetSellScore();

bool CheckFirstEntry();
bool CheckAdditionalEntry();

double CalculateNextLot(int level);
double NormalizeLot(double lot);

int    CountEAOpenPositions();
double GetEAOpenLots();

ulong  GetNewestPositionTicket();
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

double GetBasketProfit();

void LogExpertStatus();
void LogEntryBlockReason(string reason);

bool IsOurPosition(ulong ticket);

void CheckNewTradingDay();

//==================================================================
// ON INIT
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetAsyncMode(false);

   //--- Create EMA indicators
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

   //--- Create RSI indicator
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
      Print("AXIOM ERROR: Indicator initialization failed.");
      return(INIT_FAILED);
   }

   DayStartBalance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   CreateControlButtons();

   TradingEnabled =
      StartTradingOnAttach;

   Print("==================================================");
   Print("AXIOM GOLD FAST SCALPER v1.30");
   Print("INITIALIZED");
   Print("Symbol: ",_Symbol);
   Print("Signal timeframe: M1");
   Print("Daily loss limiter: REMOVED");
   Print("Consecutive loss limiter: REMOVED");
   Print("Maximum drawdown: ",
         DoubleToString(
            MaximumDrawdownPercent,2),
         "%");
   Print("Risk per trade: ",
         DoubleToString(
            MaximumRiskPercentPerTrade,2),
         "%");
   Print("Profit retrace: ",
         DoubleToString(
            BasketProfitRetrace,2));
   Print("Profit retrace percentage: ",
         DoubleToString(
            BasketProfitRetracePercent,1),
         "%");
   Print("Trading state: ",
         TradingEnabled ?
         "STARTED" :
         "STOPPED");
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

   Print("AXIOM stopped. Reason = ",reason);
}

//==================================================================
// ON TICK
//==================================================================

void OnTick()
{
   CheckNewTradingDay();

   //--- Always manage existing positions
   ManageBasket();

   //--- Emergency drawdown protection
   CheckAccountProtection();

   //--- Show Expert progress
   LogExpertStatus();

   //--- STOP prevents new entries
   if(!TradingEnabled)
      return;

   //--- Scan immediately on every tick
   CheckTradingSignals();
}

//==================================================================
// NEW TRADING DAY
//==================================================================

void CheckNewTradingDay()
{
   static int storedDay = -1;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);

   if(storedDay == -1)
   {
      storedDay = tm.day;

      DayStartBalance =
         AccountInfoDouble(
            ACCOUNT_BALANCE);

      return;
   }

   if(tm.day != storedDay)
   {
      storedDay = tm.day;

      DayStartBalance =
         AccountInfoDouble(
            ACCOUNT_BALANCE);

      BasketPeakProfit = 0.0;
      BasketPeakActive = false;

      Print("AXIOM: New trading day.");
      Print("Starting balance = $",
            DoubleToString(
               DayStartBalance,2));
   }
}

//==================================================================
// EMERGENCY DRAWDOWN PROTECTION
//==================================================================

void CheckAccountProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return;

   if(DayStartBalance <= 0.0)
      return;

   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY);

   double drawdown =
      ((DayStartBalance - equity)
      / DayStartBalance) * 100.0;

   if(drawdown >= MaximumDrawdownPercent)
   {
      if(TradingEnabled)
      {
         TradingEnabled = false;

         Print("AXIOM EMERGENCY DRAWDOWN");
         Print("Current drawdown = ",
               DoubleToString(
                  drawdown,2),
               "%");

         Print("NEW ENTRIES BLOCKED.");
         Print("Existing positions remain managed.");
      }
   }
}

//==================================================================
// CREATE START / STOP BUTTONS
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
   ObjectDelete(
      0,
      "AXIOM_START"
   );

   ObjectDelete(
      0,
      "AXIOM_STOP"
   );
}

//==================================================================
// BUTTON EVENTS
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

      Print("AXIOM: START pressed.");
      Print("New entries ENABLED.");
   }

   if(sparam == "AXIOM_STOP")
   {
      TradingEnabled = false;

      Print("AXIOM: STOP pressed.");
      Print("New entries DISABLED.");
      Print("Existing positions remain managed.");
   }
}//==================================================================
// MARKET DIRECTION
//==================================================================

int GetMarketDirection()
{
   double fast[1];
   double slow[1];
   double rsi[1];

   if(CopyBuffer(
         FastEMAHandle,
         0,
         0,
         1,
         fast) != 1)
      return 0;

   if(CopyBuffer(
         SlowEMAHandle,
         0,
         0,
         1,
         slow) != 1)
      return 0;

   if(CopyBuffer(
         RSIHandle,
         0,
         0,
         1,
         rsi) != 1)
      return 0;

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   double mid =
      (bid + ask) / 2.0;

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

   if(CopyBuffer(
         FastEMAHandle,
         0,
         0,
         1,
         fast) != 1)
      return 0.0;

   if(CopyBuffer(
         SlowEMAHandle,
         0,
         0,
         1,
         slow) != 1)
      return 0.0;

   if(CopyBuffer(
         RSIHandle,
         0,
         0,
         1,
         rsi) != 1)
      return 0.0;

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   double mid =
      (bid + ask) / 2.0;

   //--- Trend
   if(fast[0] > slow[0])
      score += 35.0;

   //--- Price position
   if(mid > fast[0])
      score += 20.0;

   //--- RSI
   if(rsi[0] >= BuyRSILevel)
      score += 30.0;

   //--- Current candle momentum
   double candleOpen =
      iOpen(
         _Symbol,
         SignalTimeframe,
         0);

   double candleClose =
      iClose(
         _Symbol,
         SignalTimeframe,
         0);

   if(candleClose > candleOpen)
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

   if(CopyBuffer(
         FastEMAHandle,
         0,
         0,
         1,
         fast) != 1)
      return 0.0;

   if(CopyBuffer(
         SlowEMAHandle,
         0,
         0,
         1,
         slow) != 1)
      return 0.0;

   if(CopyBuffer(
         RSIHandle,
         0,
         0,
         1,
         rsi) != 1)
      return 0.0;

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   double mid =
      (bid + ask) / 2.0;

   //--- Trend
   if(fast[0] < slow[0])
      score += 35.0;

   //--- Price position
   if(mid < fast[0])
      score += 20.0;

   //--- RSI
   if(rsi[0] <= SellRSILevel)
      score += 30.0;

   //--- Current candle momentum
   double candleOpen =
      iOpen(
         _Symbol,
         SignalTimeframe,
         0);

   double candleClose =
      iClose(
         _Symbol,
         SignalTimeframe,
         0);

   if(candleClose < candleOpen)
      score += 15.0;

   return score;
}

//==================================================================
// CHECK TRADING SIGNALS
//==================================================================

void CheckTradingSignals()
{
   int positions =
      CountEAOpenPositions();

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
   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   //--- No sufficient confirmation
   if(buyScore < MinimumSignalScore &&
      sellScore < MinimumSignalScore)
   {
      return false;
   }

   //--- BUY
   if(buyScore >= MinimumSignalScore &&
      buyScore > sellScore)
   {
      Print("AXIOM: BUY confirmation.");
      Print("BUY score = ",
            DoubleToString(
               buyScore,1),
            "%");

      return OpenProgressiveTrade(1);
   }

   //--- SELL
   if(sellScore >= MinimumSignalScore &&
      sellScore > buyScore)
   {
      Print("AXIOM: SELL confirmation.");
      Print("SELL score = ",
            DoubleToString(
               sellScore,1),
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
   int count =
      CountEAOpenPositions();

   if(count >= MaximumOpenPositions)
   {
      LogEntryBlockReason(
         "Maximum positions reached");

      return false;
   }

   double totalLots =
      GetEAOpenLots();

   if(totalLots >= MaximumTotalLots)
   {
      LogEntryBlockReason(
         "Maximum total lots reached");

      return false;
   }

   ulong newestTicket =
      GetNewestPositionTicket();

   if(newestTicket == 0)
      return false;

   if(!PositionSelectByTicket(
         newestTicket))
      return false;

   ENUM_POSITION_TYPE newestType =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(
         POSITION_TYPE);

   double newestPrice =
      PositionGetDouble(
         POSITION_PRICE_OPEN);

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID);

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK);

   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT);

   if(point <= 0.0)
      return false;

   double adverseDistance =
      0.0;

   //--- BUY position
   if(newestType == POSITION_TYPE_BUY)
   {
      adverseDistance =
         (newestPrice - bid)
         / point;
   }

   //--- SELL position
   if(newestType == POSITION_TYPE_SELL)
   {
      adverseDistance =
         (ask - newestPrice)
         / point;
   }

   //--- Price has not moved enough
   if(adverseDistance < AddDistancePoints)
      return false;

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   //==============================================================
   // BUY ADD
   //==============================================================

   if(newestType == POSITION_TYPE_BUY)
   {
      // Strong confirmation required
      if(RequireSignalForAdd)
      {
         if(buyScore < MinimumAddSignalScore)
         {
            LogEntryBlockReason(
               "BUY add needs stronger confirmation");

            return false;
         }

         if(buyScore <= sellScore)
         {
            LogEntryBlockReason(
               "BUY add rejected: SELL stronger");

            return false;
         }
      }

      Print("AXIOM: BUY add confirmed.");
      Print("Adverse distance = ",
            DoubleToString(
               adverseDistance,0),
            " points");

      Print("BUY score = ",
            DoubleToString(
               buyScore,1),
            "%");

      return OpenProgressiveTrade(1);
   }

   //==============================================================
   // SELL ADD
   //==============================================================

   if(newestType == POSITION_TYPE_SELL)
   {
      // Strong confirmation required
      if(RequireSignalForAdd)
      {
         if(sellScore < MinimumAddSignalScore)
         {
            LogEntryBlockReason(
               "SELL add needs stronger confirmation");

            return false;
         }

         if(sellScore <= buyScore)
         {
            LogEntryBlockReason(
               "SELL add rejected: BUY stronger");

            return false;
         }
      }

      Print("AXIOM: SELL add confirmed.");
      Print("Adverse distance = ",
            DoubleToString(
               adverseDistance,0),
            " points");

      Print("SELL score = ",
            DoubleToString(
               sellScore,1),
            "%");

      return OpenProgressiveTrade(-1);
   }

   return false;
}

//==================================================================
// CALCULATE NEXT LOT
//==================================================================

double CalculateNextLot(int level)
{
   double lot =
      StartingLot *
      MathPow(
         LotMultiplier,
         level);

   return NormalizeLot(lot);
}

//==================================================================
// NORMALIZE LOT
//==================================================================

double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   if(lot < minLot)
      lot = minLot;

   if(lot > maxLot)
      lot = maxLot;

   lot =
      MathFloor(
         lot / step) * step;

   int digits = 2;

   if(step >= 1.0)
      digits = 0;
   else if(step >= 0.1)
      digits = 1;

   return NormalizeDouble(
      lot,
      digits);
}

//==================================================================
// COUNT POSITIONS
//==================================================================

int CountEAOpenPositions()
{
   int count = 0;

   for(int i=PositionsTotal()-1;
       i>=0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(
            ticket))
         continue;

      if(PositionGetString(
            POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
            POSITION_MAGIC)
         != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//==================================================================
// TOTAL LOTS
//==================================================================

double GetEAOpenLots()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1;
       i>=0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(
            ticket))
         continue;

      if(PositionGetString(
            POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
            POSITION_MAGIC)
         != MagicNumber)
         continue;

      total +=
         PositionGetDouble(
            POSITION_VOLUME);
   }

   return total;
}

//==================================================================
// NEWEST POSITION TICKET
//==================================================================

ulong GetNewestPositionTicket()
{
   ulong newestTicket = 0;
   long newestTime = 0;

   for(int i=PositionsTotal()-1;
       i>=0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(
            ticket))
         continue;

      if(PositionGetString(
            POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
            POSITION_MAGIC)
         != MagicNumber)
         continue;

      long positionTime =
         (long)PositionGetInteger(
            POSITION_TIME_MSC);

      if(positionTime > newestTime)
      {
         newestTime = positionTime;
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
   ulong ticket =
      GetNewestPositionTicket();

   if(ticket == 0)
      return 0.0;

   if(!PositionSelectByTicket(
         ticket))
      return 0.0;

   return PositionGetDouble(
      POSITION_PRICE_OPEN);
}

//==================================================================
// RISK MONEY
//==================================================================

double CalculateRiskMoney()
{
   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE);

   return
      balance *
      MaximumRiskPercentPerTrade /
      100.0;
}

//==================================================================
// MINIMUM BROKER STOP DISTANCE
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
      MathMax(
         stopsLevel,
         freezeLevel);

   required += 10;

   return
      required * point;
}//==================================================================
// SAFE STOP LOSS
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

   if(tickSize <= 0.0 ||
      tickValue <= 0.0)
   {
      Print("AXIOM: Invalid tick information.");
      return false;
   }

   double riskMoney =
      CalculateRiskMoney();

   if(riskMoney <= 0.0)
      return false;

   double priceDistance =
      (riskMoney * tickSize)
      / (volume * tickValue);

   double minimumDistance =
      GetMinimumStopDistance();

   //--- Respect broker's minimum distance
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

   //==============================================================
   // BUY STOP
   //==============================================================

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

      if((bid - stopLoss)
         < minimumDistance)
      {
         return false;
      }
   }

   //==============================================================
   // SELL STOP
   //==============================================================

   if(orderType == ORDER_TYPE_SELL)
   {
      if(ask <= 0.0)
         return false;

      stopLoss =
         NormalizeDouble(
            ask + priceDistance,
            digits);

      if(stopLoss <= 0.0)
         return false;

      if((stopLoss - ask)
         < minimumDistance)
      {
         return false;
      }
   }

   return true;
}

//==================================================================
// OPEN PROGRESSIVE TRADE
//==================================================================

bool OpenProgressiveTrade(int direction)
{
   int level =
      CountEAOpenPositions();

   if(level >= MaximumOpenPositions)
      return false;

   double currentLots =
      GetEAOpenLots();

   double lot =
      CalculateNextLot(level);

   //--- Total exposure protection
   if(currentLots + lot >
      MaximumTotalLots)
   {
      Print("AXIOM: Maximum total exposure reached.");

      Print("Current lots = ",
            DoubleToString(
               currentLots,2));

      Print("Requested lot = ",
            DoubleToString(
               lot,2));

      return false;
   }

   ENUM_ORDER_TYPE orderType;

   if(direction > 0)
      orderType = ORDER_TYPE_BUY;
   else
      orderType = ORDER_TYPE_SELL;

   double stopLoss = 0.0;

   if(!CalculateSafeStopLoss(
         orderType,
         lot,
         stopLoss))
   {
      Print("AXIOM: Safe SL calculation failed.");
      return false;
   }

   string comment =
      "AXIOM LEVEL " +
      IntegerToString(
         level + 1);

   bool result = false;

   //==============================================================
   // BUY
   //==============================================================

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

   //==============================================================
   // SELL
   //==============================================================

   if(direction < 0)
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

      Print("Level = ",
            level + 1);

      Print("Lot = ",
            DoubleToString(
               lot,2));

      Print("Stop Loss = ",
            DoubleToString(
               stopLoss,
               (int)SymbolInfoInteger(
                  _Symbol,
                  SYMBOL_DIGITS)));

      Print("Positions = ",
            CountEAOpenPositions());

      Print("Total lots = ",
            DoubleToString(
               GetEAOpenLots(),2));

      Print("==================================================");

      return true;
   }

   Print("AXIOM: TRADE FAILED.");
   Print("Retcode = ",
         trade.ResultRetcode());

   Print("Description = ",
         trade.ResultRetcodeDescription());

   return false;
}

//==================================================================
// BASKET PROFIT
//==================================================================

double GetBasketProfit()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1;
       i>=0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(
            ticket))
         continue;

      if(PositionGetString(
            POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
            POSITION_MAGIC)
         != MagicNumber)
         continue;

      total +=
         PositionGetDouble(
            POSITION_PROFIT);

      total +=
         PositionGetDouble(
            POSITION_SWAP);
   }

   return total;
}

//==================================================================
// BASKET MANAGEMENT
//==================================================================

void ManageBasket()
{
   int count =
      CountEAOpenPositions();

   if(count <= 0)
   {
      BasketPeakProfit = 0.0;
      BasketPeakActive = false;
      return;
   }

   double basketProfit =
      GetBasketProfit();

   //==============================================================
   // ACTIVATE PROFIT PROTECTION
   //==============================================================

   if(basketProfit > 0.0)
   {
      if(!BasketPeakActive)
      {
         BasketPeakActive = true;
         BasketPeakProfit = basketProfit;

         Print("AXIOM: PROFIT PROTECTION ACTIVATED.");
         Print("Peak profit = $",
               DoubleToString(
                  BasketPeakProfit,2));
      }

      //--- New peak
      if(basketProfit >
         BasketPeakProfit)
      {
         BasketPeakProfit =
            basketProfit;

         Print("AXIOM: NEW PROFIT PEAK = $",
               DoubleToString(
                  BasketPeakProfit,2));
      }
   }

   //==============================================================
   // FIXED PROFIT TARGET
   //==============================================================

   if(basketProfit >=
      BasketProfitTarget)
   {
      Print("AXIOM: BASKET TARGET REACHED.");
      Print("Basket profit = $",
            DoubleToString(
               basketProfit,2));

      CloseProfitableBasket();

      return;
   }

   //==============================================================
   // PROFIT RETRACEMENT
   //==============================================================

   if(!UseProfitRetrace)
      return;

   if(!BasketPeakActive)
      return;

   if(BasketPeakProfit <= 0.0)
      return;

   //--- Fixed money protection
   double fixedLevel =
      BasketPeakProfit -
      BasketProfitRetrace;

   //--- Percentage protection
   double percentLevel =
      BasketPeakProfit *
      (1.0 -
       BasketProfitRetracePercent /
       100.0);

   //--- Use the HIGHER protection level.
   //--- This protects profit sooner.
   double protectionLevel =
      MathMax(
         fixedLevel,
         percentLevel);

   if(basketProfit <= protectionLevel &&
      basketProfit > 0.0)
   {
      Print("AXIOM: PROFIT RETRACEMENT TRIGGERED.");

      Print("Peak = $",
            DoubleToString(
               BasketPeakProfit,2));

      Print("Current = $",
            DoubleToString(
               basketProfit,2));

      Print("Protection level = $",
            DoubleToString(
               protectionLevel,2));

      CloseProfitableBasket();
   }
}

//==================================================================
// CLOSE ONLY PROFITABLE POSITIONS
//==================================================================

void CloseProfitableBasket()
{
   double basketProfit =
      GetBasketProfit();

   //==============================================================
   // NEVER CLOSE A LOSING BASKET
   //==============================================================

   if(basketProfit <= 0.0)
   {
      Print("AXIOM: Basket is not profitable.");
      Print("NO PROFIT EXIT PERFORMED.");

      return;
   }

   bool closedSomething = false;

   //==============================================================
   // CLOSE PROFITABLE POSITIONS ONLY
   //==============================================================

   for(int i=PositionsTotal()-1;
       i>=0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(
            ticket))
         continue;

      if(PositionGetString(
            POSITION_SYMBOL)
         != _Symbol)
         continue;

      if((long)PositionGetInteger(
            POSITION_MAGIC)
         != MagicNumber)
         continue;

      double profit =
         PositionGetDouble(
            POSITION_PROFIT);

      //--- VERY IMPORTANT:
      //--- Losing positions are NOT closed here.
      if(profit <= 0.0)
         continue;

      if(trade.PositionClose(
            ticket))
      {
         closedSomething = true;

         Print("AXIOM: PROFITABLE POSITION CLOSED.");
         Print("Ticket = ",ticket);

         Print("Profit = $",
               DoubleToString(
                  profit,2));
      }
      else
      {
         Print("AXIOM: Could not close profitable position.");
         Print("Ticket = ",ticket);

         Print("Reason = ",
               trade.ResultRetcodeDescription());
      }
   }

   if(closedSomething)
   {
      BasketPeakProfit = 0.0;
      BasketPeakActive = false;

      Print("AXIOM: PROFIT PROTECTION CYCLE COMPLETE.");
   }
}

//==================================================================
// OUR POSITION CHECK
//==================================================================

bool IsOurPosition(ulong ticket)
{
   if(ticket == 0)
      return false;

   if(!PositionSelectByTicket(
         ticket))
      return false;

   if(PositionGetString(
         POSITION_SYMBOL)
      != _Symbol)
      return false;

   if((long)PositionGetInteger(
         POSITION_MAGIC)
      != MagicNumber)
      return false;

   return true;
}

//==================================================================
// EXPERT STATUS
//==================================================================

void LogExpertStatus()
{
   datetime now =
      TimeCurrent();

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

   string directionText =
      "NEUTRAL";

   if(direction > 0)
      directionText = "BUY";

   if(direction < 0)
      directionText = "SELL";

   Print(
      "AXIOM STATUS | ",
      "STATE=",
      TradingEnabled ?
      "STARTED" :
      "STOPPED",

      " | DIRECTION=",
      directionText,

      " | BUY=",
      DoubleToString(
         buyScore,1),
      "%",

      " | SELL=",
      DoubleToString(
         sellScore,1),
      "%",

      " | POSITIONS=",
      CountEAOpenPositions(),

      " | LOTS=",
      DoubleToString(
         GetEAOpenLots(),2),

      " | BASKET=$",
      DoubleToString(
         basket,2),

      " | PEAK=$",
      DoubleToString(
         BasketPeakProfit,2)
   );
}

//==================================================================
// ENTRY BLOCK MESSAGE
//==================================================================

void LogEntryBlockReason(
   string reason
)
{
   datetime now =
      TimeCurrent();

   if(now - LastBlockLogTime < 3)
      return;

   LastBlockLogTime = now;

   Print(
      "AXIOM ENTRY WAITING: ",
      reason
   );
}//+------------------------------------------------------------------+
