//+------------------------------------------------------------------+
//|              AXIOM GOLD FAST SCALPER                             |
//|              Live Tick Axiom-Style Reconstruction                |
//|              XAUUSD / M1                                         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "Fast live-tick XAUUSD scalper with progressive basket entries"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

//--- General
input bool   StartTradingOnAttach        = false;
input long   MagicNumber                 = 26092027;
input int    SlippagePoints              = 20;

//--- Signal
input ENUM_TIMEFRAMES SignalTimeframe    = PERIOD_M1;
input int    FastEMAPeriod               = 9;
input int    SlowEMAPeriod               = 21;
input int    RSIPeriod                   = 14;

input double BuyRSILevel                 = 52.0;
input double SellRSILevel                = 48.0;

input double MinimumSignalScore          = 70.0;

//--- Progressive positions
input double StartingLot                 = 0.01;
input double LotMultiplier               = 2.0;

input int    MaximumOpenPositions        = 6;
input double MaximumTotalLots            = 0.64;

//--- Additional entries
input double AddDistancePoints           = 300.0;
input bool   RequireSignalForAdd         = true;

//--- Basket profit
input double BasketProfitTarget          = 2.00;
input double BasketProfitRetrace         = 0.50;
input bool   UseProfitRetrace             = true;

//--- Risk
input double MaximumRiskPercentPerTrade  = 0.50;
input double DailyLossLimitPercent       = 2.0;
input double MaximumDrawdownPercent      = 5.0;

//--- Loss protection
input int    MaximumConsecutiveLosses    = 3;

//--- Status
input int    StatusIntervalSeconds       = 3;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

int FastEMAHandle = INVALID_HANDLE;
int SlowEMAHandle = INVALID_HANDLE;
int RSIHandle     = INVALID_HANDLE;

bool TradingEnabled = false;
bool ProtectionLocked = false;

double DayStartBalance = 0.0;
double BasketPeakProfit = 0.0;

int ConsecutiveLosses = 0;

datetime LastStatusTime = 0;
datetime LastDayCheck = 0;

//--- chart buttons
string StartButtonName = "AXIOM_START_BUTTON";
string StopButtonName  = "AXIOM_STOP_BUTTON";

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   //--- indicator handles
   FastEMAHandle =
      iMA(_Symbol,
          SignalTimeframe,
          FastEMAPeriod,
          0,
          MODE_EMA,
          PRICE_CLOSE);

   SlowEMAHandle =
      iMA(_Symbol,
          SignalTimeframe,
          SlowEMAPeriod,
          0,
          MODE_EMA,
          PRICE_CLOSE);

   RSIHandle =
      iRSI(_Symbol,
           SignalTimeframe,
           RSIPeriod,
           PRICE_CLOSE);

   if(FastEMAHandle == INVALID_HANDLE ||
      SlowEMAHandle == INVALID_HANDLE ||
      RSIHandle == INVALID_HANDLE)
   {
      Print("AXIOM ERROR: Indicator initialization failed.");
      return(INIT_FAILED);
   }

   //--- account starting point
   DayStartBalance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   LastDayCheck = TimeCurrent();

   TradingEnabled = StartTradingOnAttach;

   CreateButtons();

   Print("==================================================");
   Print("AXIOM GOLD FAST SCALPER v1.10");
   Print("Symbol: ",_Symbol);
   Print("Signal timeframe: M1");
   Print("LIVE TICK SCANNING: ENABLED");
   Print("CANDLE CLOSE WAIT: DISABLED");
   Print("Starting lot: ",
         DoubleToString(StartingLot,2));
   Print("Lot multiplier: ",
         DoubleToString(LotMultiplier,2));
   Print("Maximum positions: ",
         MaximumOpenPositions);
   Print("Maximum total lots: ",
         DoubleToString(MaximumTotalLots,2));
   Print("Risk target per trade: ",
         DoubleToString(MaximumRiskPercentPerTrade,2),
         "%");
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================

void OnDeinit(const int reason)
{
   if(FastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(FastEMAHandle);

   if(SlowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(SlowEMAHandle);

   if(RSIHandle != INVALID_HANDLE)
      IndicatorRelease(RSIHandle);

   ObjectDelete(0,StartButtonName);
   ObjectDelete(0,StopButtonName);

   Print("AXIOM: EA stopped. Reason = ",reason);
}

//==================================================================
// MAIN TICK ENGINE
//==================================================================

void OnTick()
{
   //--- reset daily protection if necessary
   CheckNewTradingDay();

   //--- manage existing profitable basket FIRST
   ManageBasket();

   //--- account protection
   if(CheckAccountProtection())
   {
      LogStatusIfNeeded();
      return;
   }

   //--- stopped means no NEW entries
   //--- existing trades remain managed
   if(!TradingEnabled)
   {
      LogStatusIfNeeded();
      return;
   }

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   if(tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   //==============================================================
   // FIND CURRENT LIVE DIRECTION
   //==============================================================

   int direction = GetMarketDirection();

   if(direction == 0)
   {
      LogStatusIfNeeded();
      return;
   }

   int positions = CountOurPositions();

   //==============================================================
   // FIRST ENTRY
   //==============================================================

   if(positions == 0)
   {
      CheckFirstEntry(direction);
      LogStatusIfNeeded();
      return;
   }

   //==============================================================
   // ADDITIONAL FAST ENTRY
   //==============================================================

   CheckAdditionalEntry(direction);

   LogStatusIfNeeded();
}

//==================================================================
// CREATE BUTTONS
//==================================================================

void CreateButtons()
{
   ObjectCreate(0,
                StartButtonName,
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    StartButtonName,
                    OBJPROP_XDISTANCE,
                    20);

   ObjectSetInteger(0,
                    StartButtonName,
                    OBJPROP_YDISTANCE,
                    30);

   ObjectSetInteger(0,
                    StartButtonName,
                    OBJPROP_XSIZE,
                    110);

   ObjectSetInteger(0,
                    StartButtonName,
                    OBJPROP_YSIZE,
                    35);

   ObjectSetString(0,
                   StartButtonName,
                   OBJPROP_TEXT,
                   "START");

   ObjectCreate(0,
                StopButtonName,
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    StopButtonName,
                    OBJPROP_XDISTANCE,
                    140);

   ObjectSetInteger(0,
                    StopButtonName,
                    OBJPROP_YDISTANCE,
                    30);

   ObjectSetInteger(0,
                    StopButtonName,
                    OBJPROP_XSIZE,
                    110);

   ObjectSetInteger(0,
                    StopButtonName,
                    OBJPROP_YSIZE,
                    35);

   ObjectSetString(0,
                   StopButtonName,
                   OBJPROP_TEXT,
                   "STOP");

   ChartRedraw();
}

//==================================================================
// BUTTON EVENTS
//==================================================================

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == StartButtonName)
   {
      TradingEnabled = true;

      Print("AXIOM: START pressed.");
      Print("AXIOM: LIVE SCANNING ACTIVE.");
   }

   if(sparam == StopButtonName)
   {
      TradingEnabled = false;

      Print("AXIOM: STOP pressed.");
      Print("AXIOM: New entries stopped.");
      Print("AXIOM: Existing positions remain managed.");
   }
}

//==================================================================
// NEW DAY CHECK
//==================================================================

void CheckNewTradingDay()
{
   datetime now = TimeCurrent();

   MqlDateTime currentTime;
   MqlDateTime previousTime;

   TimeToStruct(now,currentTime);
   TimeToStruct(LastDayCheck,previousTime);

   if(currentTime.day != previousTime.day ||
      currentTime.mon != previousTime.mon ||
      currentTime.year != previousTime.year)
   {
      DayStartBalance =
         AccountInfoDouble(ACCOUNT_BALANCE);

      ConsecutiveLosses = 0;
      ProtectionLocked = false;
      BasketPeakProfit = 0.0;

      LastDayCheck = now;

      Print("AXIOM: NEW TRADING DAY.");
      Print("AXIOM: Daily protections reset.");
   }
}

//==================================================================
// ACCOUNT PROTECTION
//==================================================================

bool CheckAccountProtection()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(DayStartBalance <= 0.0)
      return(false);

   //--- daily loss
   double dailyLoss =
      (DayStartBalance - equity) /
      DayStartBalance * 100.0;

   if(dailyLoss >= DailyLossLimitPercent)
   {
      if(!ProtectionLocked)
      {
         ProtectionLocked = true;

         Print("AXIOM PROTECTION:");
         Print("Daily loss limit reached.");
         Print("New entries BLOCKED.");
      }

      return(true);
   }

   //--- drawdown from start-of-day balance
   double drawdown =
      (DayStartBalance - equity) /
      DayStartBalance * 100.0;

   if(drawdown >= MaximumDrawdownPercent)
   {
      if(!ProtectionLocked)
      {
         ProtectionLocked = true;

         Print("AXIOM PROTECTION:");
         Print("Maximum drawdown reached.");
         Print("New entries BLOCKED.");
      }

      return(true);
   }

   //--- consecutive losses
   if(ConsecutiveLosses >= MaximumConsecutiveLosses)
   {
      if(!ProtectionLocked)
      {
         ProtectionLocked = true;

         Print("AXIOM PROTECTION:");
         Print("Maximum consecutive losses reached.");
         Print("New entries BLOCKED.");
      }

      return(true);
   }

   return(false);
}//==================================================================
// MARKET DIRECTION
//==================================================================

int GetMarketDirection()
{
   double fastEMA[1];
   double slowEMA[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fastEMA) != 1)
      return(0);

   if(CopyBuffer(SlowEMAHandle,0,0,1,slowEMA) != 1)
      return(0);

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return(0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return(0);

   double price =
      (tick.bid + tick.ask) / 2.0;

   double buyScore = 0.0;
   double sellScore = 0.0;

   //--- EMA trend
   if(fastEMA[0] > slowEMA[0])
      buyScore += 35.0;

   if(fastEMA[0] < slowEMA[0])
      sellScore += 35.0;

   //--- price relative to fast EMA
   if(price > fastEMA[0])
      buyScore += 20.0;

   if(price < fastEMA[0])
      sellScore += 20.0;

   //--- RSI
   if(rsi[0] >= BuyRSILevel)
      buyScore += 30.0;

   if(rsi[0] <= SellRSILevel)
      sellScore += 30.0;

   if(buyScore >= MinimumSignalScore &&
      buyScore > sellScore)
   {
      return(1);
   }

   if(sellScore >= MinimumSignalScore &&
      sellScore > buyScore)
   {
      return(-1);
   }

   return(0);
}

//==================================================================
// BUY SCORE
//==================================================================

double GetBuyScore()
{
   double fastEMA[1];
   double slowEMA[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fastEMA) != 1)
      return(0.0);

   if(CopyBuffer(SlowEMAHandle,0,0,1,slowEMA) != 1)
      return(0.0);

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return(0.0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return(0.0);

   double price =
      (tick.bid + tick.ask) / 2.0;

   double score = 0.0;

   if(fastEMA[0] > slowEMA[0])
      score += 35.0;

   if(price > fastEMA[0])
      score += 20.0;

   if(rsi[0] >= BuyRSILevel)
      score += 30.0;

   //--- current live candle momentum
   double candleOpen =
      iOpen(_Symbol,
            SignalTimeframe,
            0);

   if(candleOpen > 0.0 &&
      price > candleOpen)
   {
      score += 15.0;
   }

   return(score);
}

//==================================================================
// SELL SCORE
//==================================================================

double GetSellScore()
{
   double fastEMA[1];
   double slowEMA[1];
   double rsi[1];

   if(CopyBuffer(FastEMAHandle,0,0,1,fastEMA) != 1)
      return(0.0);

   if(CopyBuffer(SlowEMAHandle,0,0,1,slowEMA) != 1)
      return(0.0);

   if(CopyBuffer(RSIHandle,0,0,1,rsi) != 1)
      return(0.0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return(0.0);

   double price =
      (tick.bid + tick.ask) / 2.0;

   double score = 0.0;

   if(fastEMA[0] < slowEMA[0])
      score += 35.0;

   if(price < fastEMA[0])
      score += 20.0;

   if(rsi[0] <= SellRSILevel)
      score += 30.0;

   //--- current live candle momentum
   double candleOpen =
      iOpen(_Symbol,
            SignalTimeframe,
            0);

   if(candleOpen > 0.0 &&
      price < candleOpen)
   {
      score += 15.0;
   }

   return(score);
}

//==================================================================
// FIRST ENTRY
//==================================================================

void CheckFirstEntry(const int direction)
{
   double buyScore = GetBuyScore();
   double sellScore = GetSellScore();

   Print("AXIOM SCAN | BUY=",
         DoubleToString(buyScore,1),
         "% | SELL=",
         DoubleToString(sellScore,1),
         "%");

   if(direction == 1 &&
      buyScore >= MinimumSignalScore &&
      buyScore > sellScore)
   {
      Print("AXIOM: BUY confirmation.");
      OpenProgressiveTrade(ORDER_TYPE_BUY,0);
      return;
   }

   if(direction == -1 &&
      sellScore >= MinimumSignalScore &&
      sellScore > buyScore)
   {
      Print("AXIOM: SELL confirmation.");
      OpenProgressiveTrade(ORDER_TYPE_SELL,0);
      return;
   }
}

//==================================================================
// ADDITIONAL FAST ENTRY
//==================================================================

void CheckAdditionalEntry(const int direction)
{
   int positions =
      CountOurPositions();

   if(positions <= 0)
      return;

   if(positions >= MaximumOpenPositions)
      return;

   double totalLots =
      GetTotalOurLots();

   if(totalLots >= MaximumTotalLots)
   {
      Print("AXIOM: Maximum total exposure reached.");
      return;
   }

   ulong newestTicket =
      GetNewestPositionTicket();

   if(newestTicket == 0)
      return;

   if(!PositionSelectByTicket(newestTicket))
      return;

   long positionType =
      PositionGetInteger(POSITION_TYPE);

   double lastEntry =
      PositionGetDouble(POSITION_PRICE_OPEN);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double currentPrice;

   if(positionType == POSITION_TYPE_BUY)
      currentPrice = tick.bid;
   else
      currentPrice = tick.ask;

   double distance =
      MathAbs(currentPrice - lastEntry) /
      _Point;

   if(distance < AddDistancePoints)
      return;

   //--- do not add against the existing direction
   if(direction == 1 &&
      positionType != POSITION_TYPE_BUY)
      return;

   if(direction == -1 &&
      positionType != POSITION_TYPE_SELL)
      return;

   //--- require fresh confirmation
   if(positionType == POSITION_TYPE_BUY)
   {
      double score = GetBuyScore();

      if(!RequireSignalForAdd ||
         score >= MinimumSignalScore)
      {
         Print("AXIOM: FAST BUY ADD.");
         Print("Confirmation score=",
               DoubleToString(score,1),
               "%");

         OpenProgressiveTrade(ORDER_TYPE_BUY,
                              positions);
      }
   }

   if(positionType == POSITION_TYPE_SELL)
   {
      double score = GetSellScore();

      if(!RequireSignalForAdd ||
         score >= MinimumSignalScore)
      {
         Print("AXIOM: FAST SELL ADD.");
         Print("Confirmation score=",
               DoubleToString(score,1),
               "%");

         OpenProgressiveTrade(ORDER_TYPE_SELL,
                              positions);
      }
   }
}

//==================================================================
// VOLUME DIGITS
//==================================================================

int VolumeDigits(const double step)
{
   if(step >= 1.0)
      return(0);

   if(step >= 0.1)
      return(1);

   if(step >= 0.01)
      return(2);

   return(3);
}

//==================================================================
// NORMALIZE LOT
//==================================================================

double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0)
      minLot = 0.01;

   if(maxLot <= 0.0)
      maxLot = MaximumTotalLots;

   if(step <= 0.0)
      step = 0.01;

   lot = MathMax(lot,minLot);
   lot = MathMin(lot,maxLot);

   lot = MathFloor(lot / step) * step;

   return NormalizeDouble(lot,
                          VolumeDigits(step));
}

//==================================================================
// PROGRESSIVE LOT
//==================================================================

double CalculateProgressiveLot(const int level)
{
   double lot =
      StartingLot *
      MathPow(LotMultiplier,level);

   return NormalizeLot(lot);
}

//==================================================================
// TOTAL LOTS
//==================================================================

double GetTotalOurLots()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)
         != MagicNumber)
         continue;

      total +=
         PositionGetDouble(POSITION_VOLUME);
   }

   return(total);
}

//==================================================================
// POSITION COUNT
//==================================================================

int CountOurPositions()
{
   int count = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)
         != MagicNumber)
         continue;

      count++;
   }

   return(count);
}

//==================================================================
// NEWEST POSITION
//==================================================================

ulong GetNewestPositionTicket()
{
   ulong newestTicket = 0;
   long newestTime = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)
         != MagicNumber)
         continue;

      long positionTime =
         PositionGetInteger(POSITION_TIME_MSC);

      if(positionTime > newestTime)
      {
         newestTime = positionTime;
         newestTicket = ticket;
      }
   }

   return(newestTicket);
}

//==================================================================
// RISK MONEY
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
// CALCULATE SAFE STOP DISTANCE
//==================================================================

double GetMinimumStopDistance()
{
   double point =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_POINT);

   long stopsLevel =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_STOPS_LEVEL);

   long freezeLevel =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_FREEZE_LEVEL);

   double distance =
      MathMax((double)stopsLevel,
              (double)freezeLevel) *
      point;

   //--- extra safety for fast XAUUSD movement
   distance += 10.0 * point;

   return(distance);
}

//==================================================================
// CALCULATE RISK-BASED STOP
//==================================================================

bool CalculateSafeStopLoss(const ENUM_ORDER_TYPE orderType,
                           const double volume,
                           double &stopLoss)
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return(false);

   double tickSize =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_VALUE);

   double point =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_POINT);

   int digits =
      (int)SymbolInfoInteger(_Symbol,
                             SYMBOL_DIGITS);

   if(tickSize <= 0.0 ||
      tickValue <= 0.0 ||
      point <= 0.0 ||
      volume <= 0.0)
   {
      Print("AXIOM: Invalid XAUUSD trading specifications.");
      return(false);
   }

   double riskMoney =
      CalculateRiskMoney();

   double riskDistance =
      (riskMoney * tickSize) /
      (volume * tickValue);

   double minimumDistance =
      GetMinimumStopDistance();

   //==============================================================
   // BUY
   //==============================================================

   if(orderType == ORDER_TYPE_BUY)
   {
      double sl =
         tick.bid - riskDistance;

      double maximumAllowedSL =
         tick.bid - minimumDistance;

      //--- if calculated SL is too close,
      //--- use broker-valid minimum distance
      if(sl > maximumAllowedSL)
         sl = maximumAllowedSL;

      if(sl <= 0.0)
      {
         Print("AXIOM: Invalid BUY stop price.");
         return(false);
      }

      stopLoss =
         NormalizeDouble(sl,digits);

      return(true);
   }

   //==============================================================
   // SELL
   //==============================================================

   if(orderType == ORDER_TYPE_SELL)
   {
      double sl =
         tick.ask + riskDistance;

      double minimumAllowedSL =
         tick.ask + minimumDistance;

      //--- if calculated SL is too close,
      //--- use broker-valid minimum distance
      if(sl < minimumAllowedSL)
         sl = minimumAllowedSL;

      stopLoss =
         NormalizeDouble(sl,digits);

      return(true);
   }

   return(false);
}//==================================================================
// OPEN PROGRESSIVE TRADE
//==================================================================

void OpenProgressiveTrade(const ENUM_ORDER_TYPE orderType,
                          const int level)
{
   //--- position limit
   if(CountOurPositions() >= MaximumOpenPositions)
      return;

   double requestedLot =
      CalculateProgressiveLot(level);

   if(requestedLot <= 0.0)
      return;

   double currentLots =
      GetTotalOurLots();

   double remainingExposure =
      MaximumTotalLots - currentLots;

   if(remainingExposure <= 0.0)
   {
      Print("AXIOM: No remaining exposure available.");
      return;
   }

   double lot =
      MathMin(requestedLot,
              remainingExposure);

   lot = NormalizeLot(lot);

   if(lot <= 0.0)
      return;

   //--- make sure minimum lot does not exceed exposure
   if(currentLots + lot > MaximumTotalLots + 0.0000001)
   {
      Print("AXIOM: Exposure protection blocked entry.");
      return;
   }

   //--- get live price
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double stopLoss = 0.0;

   if(!CalculateSafeStopLoss(orderType,
                             lot,
                             stopLoss))
   {
      Print("AXIOM: Could not create valid protective stop.");
      return;
   }

   string comment =
      "AXIOM-L" +
      IntegerToString(level + 1);

   bool result = false;

   ResetLastError();

   //==============================================================
   // FAST BUY
   //==============================================================

   if(orderType == ORDER_TYPE_BUY)
   {
      result =
         trade.Buy(lot,
                   _Symbol,
                   0.0,
                   stopLoss,
                   0.0,
                   comment);
   }

   //==============================================================
   // FAST SELL
   //==============================================================

   if(orderType == ORDER_TYPE_SELL)
   {
      result =
         trade.Sell(lot,
                    _Symbol,
                    0.0,
                    stopLoss,
                    0.0,
                    comment);
   }

   //==============================================================
   // RESULT
   //==============================================================

   if(result)
   {
      Print("==================================================");
      Print("AXIOM FAST ENTRY EXECUTED");
      Print("Direction: ",
            orderType == ORDER_TYPE_BUY ?
            "BUY" : "SELL");

      Print("Level: ",level + 1);

      Print("Lot: ",
            DoubleToString(lot,2));

      Print("SL: ",
            DoubleToString(stopLoss,_Digits));

      Print("Positions: ",
            CountOurPositions());

      Print("Total lots: ",
            DoubleToString(GetTotalOurLots(),2));

      Print("Risk target: ",
            DoubleToString(
               MaximumRiskPercentPerTrade,2),
            "%");

      Print("==================================================");

      BasketPeakProfit =
         GetBasketProfit();
   }
   else
   {
      Print("AXIOM ENTRY FAILED");
      Print("Retcode: ",
            trade.ResultRetcode());

      Print("Description: ",
            trade.ResultRetcodeDescription());

      Print("Last error: ",
            GetLastError());

      Print("Lot attempted: ",
            DoubleToString(lot,2));

      Print("SL attempted: ",
            DoubleToString(stopLoss,_Digits));
   }
}

//==================================================================
// BASKET MANAGEMENT
//==================================================================

void ManageBasket()
{
   int count =
      CountOurPositions();

   if(count <= 0)
   {
      BasketPeakProfit = 0.0;
      return;
   }

   double basketProfit =
      GetBasketProfit();

   //--- update peak
   if(basketProfit > BasketPeakProfit)
      BasketPeakProfit = basketProfit;

   //==============================================================
   // BASKET TARGET
   //==============================================================

   if(basketProfit >= BasketProfitTarget)
   {
      Print("AXIOM: BASKET TARGET REACHED.");
      Print("Basket profit = $",
            DoubleToString(basketProfit,2));

      CloseProfitableBasket();

      return;
   }

   //==============================================================
   // PROFIT RETRACEMENT
   //==============================================================

   if(UseProfitRetrace &&
      BasketPeakProfit > 0.0)
   {
      double protectionLevel =
         BasketPeakProfit -
         BasketProfitRetrace;

      if(basketProfit <= protectionLevel &&
         basketProfit > 0.0)
      {
         Print("AXIOM: PROFIT RETRACEMENT.");
         Print("Peak = $",
               DoubleToString(BasketPeakProfit,2));

         Print("Current = $",
               DoubleToString(basketProfit,2));

         CloseProfitableBasket();

         return;
      }
   }
}

//==================================================================
// BASKET PROFIT
//==================================================================

double GetBasketProfit()
{
   double total = 0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)
         != MagicNumber)
         continue;

      total +=
         PositionGetDouble(POSITION_PROFIT);

      total +=
         PositionGetDouble(POSITION_SWAP);
   }

   return(total);
}

//==================================================================
// CLOSE PROFITABLE BASKET
//==================================================================

void CloseProfitableBasket()
{
   double basket =
      GetBasketProfit();

   //--- IMPORTANT:
   //--- never intentionally close when total basket is negative
   if(basket <= 0.0)
   {
      Print("AXIOM: Basket is not profitable.");
      Print("No basket closure performed.");
      return;
   }

   Print("AXIOM: Closing profitable positions.");

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)
         != MagicNumber)
         continue;

      double profit =
         PositionGetDouble(POSITION_PROFIT);

      //--- preserve losing positions
      if(profit <= 0.0)
      {
         Print("AXIOM: Losing position remains open.");
         Print("Ticket = ",ticket);
         Print("Profit = $",
               DoubleToString(profit,2));

         continue;
      }

      if(trade.PositionClose(ticket))
      {
         Print("AXIOM: Profit position closed.");
         Print("Ticket = ",ticket);
      }
      else
      {
         Print("AXIOM: Position close failed.");
         Print("Ticket = ",ticket);
         Print("Retcode = ",
               trade.ResultRetcode());
         Print("Description = ",
               trade.ResultRetcodeDescription());
      }
   }

   BasketPeakProfit = 0.0;
}

//==================================================================
// STATUS LOG
//==================================================================

void LogStatusIfNeeded()
{
   datetime now =
      TimeCurrent();

   if(LastStatusTime != 0 &&
      now - LastStatusTime <
      StatusIntervalSeconds)
      return;

   LastStatusTime = now;

   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   double basket =
      GetBasketProfit();

   int positions =
      CountOurPositions();

   double lots =
      GetTotalOurLots();

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   Print("AXIOM STATUS | ",
         TradingEnabled ?
         "RUNNING" : "STOPPED",
         " | BUY=",
         DoubleToString(buyScore,1),
         "% | SELL=",
         DoubleToString(sellScore,1),
         "% | POS=",
         positions,
         " | LOTS=",
         DoubleToString(lots,2),
         " | BASKET=$",
         DoubleToString(basket,2),
         " | BAL=$",
         DoubleToString(balance,2),
         " | EQ=$",
         DoubleToString(equity,2),
         " | LOSS STREAK=",
         ConsecutiveLosses);
}

//==================================================================
// TRADE TRANSACTION
//==================================================================

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket =
      trans.deal;

   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   string symbol =
      HistoryDealGetString(
         dealTicket,
         DEAL_SYMBOL);

   if(symbol != _Symbol)
      return;

   long magic =
      HistoryDealGetInteger(
         dealTicket,
         DEAL_MAGIC);

   if(magic != MagicNumber)
      return;

   long entry =
      HistoryDealGetInteger(
         dealTicket,
         DEAL_ENTRY);

   //--- only completed exits
   if(entry != DEAL_ENTRY_OUT &&
      entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_PROFIT);

   double swap =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_SWAP);

   double commission =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_COMMISSION);

   double net =
      profit +
      swap +
      commission;

   if(net < 0.0)
   {
      ConsecutiveLosses++;

      Print("AXIOM LOSS");
      Print("Net result = $",
            DoubleToString(net,2));

      Print("Consecutive losses = ",
            ConsecutiveLosses);

      if(ConsecutiveLosses >=
         MaximumConsecutiveLosses)
      {
         ProtectionLocked = true;

         Print("AXIOM PROTECTION:");
         Print("Maximum consecutive losses reached.");
         Print("NEW ENTRIES BLOCKED.");
      }
   }
   else
   if(net > 0.0)
   {
      ConsecutiveLosses = 0;

      Print("AXIOM WIN");
      Print("Net result = $",
            DoubleToString(net,2));

      Print("Loss streak reset.");
   }
}

//==================================================================
// END OF EA
//==================================================================
