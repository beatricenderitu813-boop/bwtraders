//+------------------------------------------------------------------+
//| M1_TREND_CONTINUATION_SCALPER_AI_v6.mq5                         |
//| M1 Trend Continuation Scalper                                    |
//+------------------------------------------------------------------+
#property strict
#property version   "6.00"
#property description "M1 trend continuation scalper with structure SL and closer TP"

#include <Trade/Trade.mqh>

CTrade trade;

//-------------------------------------------------------------------
// Trend constants
//-------------------------------------------------------------------
#define TREND_NONE  0
#define TREND_BUY   1
#define TREND_SELL -1

//-------------------------------------------------------------------
// INPUTS
//-------------------------------------------------------------------
input bool   StartTradingOnAttach      = false;
input ulong  MagicNumber               = 26092026;

input double SignalThreshold           = 70.0;

// Dynamic lot:
// $10   = 0.01
// $100  = 0.10
// $1000 = 1.00
input double LotMultiplier              = 0.001;
input double MaximumLotSize             = 10.0;

input int    StructureLookback          = 5;
input int    ContinuationLookback       = 5;
input int    ReverseBreakoutLookback    = 5;

input double MinimumBodyPercent         = 50.0;

// SL is placed beyond recent structure.
input int    SLBufferPoints             = 50;

// IMPORTANT:
// TP is deliberately closer than SL.
// Example:
// SL distance = $2
// TP distance = $1
input double TakeProfitRiskRatio        = 0.50;

input int    MaximumOpenPositions       = 1;
input double MaximumEAExposureLots     = 10.0;

input double DailyLossLimitPercent      = 2.0;
input double MaximumDrawdownPercent     = 5.0;
input int    MaximumConsecutiveLosses   = 3;

input int    SlippagePoints              = 20;

//-------------------------------------------------------------------
// GLOBAL VARIABLES
//-------------------------------------------------------------------
bool   TradingEnabled = false;

int    CurrentTrend = TREND_NONE;

double DayStartBalance = 0.0;
double PeakEquity      = 0.0;

int    ConsecutiveLosses = 0;

int    LastTradingDayKey = 0;

//-------------------------------------------------------------------
// FUNCTION DECLARATIONS
//-------------------------------------------------------------------
void   CreateControlButtons();
void   UpdateStatus();

void   ResetDailyStatisticsIfNeeded();
void   UpdatePeakEquity();

bool   CanTrade();
bool   DailyLossProtection();
bool   DrawdownProtection();
bool   ConsecutiveLossProtection();

double CalculateLotSize();
double NormalizeVolume(double volume);

int    CountOpenPositions();
double GetCurrentExposureLots();

bool   EnoughM1Bars();

double GetHighestHigh(int startShift, int count);
double GetLowestLow(int startShift, int count);

bool   IsBullishStructure();
bool   IsBearishStructure();

bool   BullishMomentum();
bool   BearishMomentum();

bool   BullishContinuationBreakout();
bool   BearishContinuationBreakout();

bool   BullishReverseBreakout();
bool   BearishReverseBreakout();

int    DetectInitialTrend();
void   UpdateTrendState();

double GetBuyScore();
double GetSellScore();

void   CheckForEntry();

bool   OpenBuy();
bool   OpenSell();

void   UpdateConsecutiveLossesFromDeal(ulong dealTicket);

//-------------------------------------------------------------------
// ON INIT
//-------------------------------------------------------------------
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   PeakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);

   LastTradingDayKey = 0;
   ConsecutiveLosses = 0;
   CurrentTrend     = TREND_NONE;

   TradingEnabled = StartTradingOnAttach;

   CreateControlButtons();
   UpdateStatus();

   return(INIT_SUCCEEDED);
}

//-------------------------------------------------------------------
// ON DEINIT
//-------------------------------------------------------------------
void OnDeinit(const int reason)
{
   ObjectDelete(0, "M1SCALPER_START");
   ObjectDelete(0, "M1SCALPER_STOP");
   Comment("");
}

//-------------------------------------------------------------------
// ON TICK
//-------------------------------------------------------------------
void OnTick()
{
   ResetDailyStatisticsIfNeeded();
   UpdatePeakEquity();

   if(!EnoughM1Bars())
   {
      UpdateStatus();
      return;
   }

   UpdateTrendState();
   UpdateStatus();

   if(!TradingEnabled)
      return;

   CheckForEntry();
}

//-------------------------------------------------------------------
// CHART EVENT
//-------------------------------------------------------------------
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "M1SCALPER_START")
   {
      TradingEnabled = true;
      UpdateStatus();
      ChartRedraw();
   }

   if(sparam == "M1SCALPER_STOP")
   {
      TradingEnabled = false;
      UpdateStatus();
      ChartRedraw();
   }
}

//-------------------------------------------------------------------
// TRADE TRANSACTION
//-------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(trans.deal == 0)
      return;

   UpdateConsecutiveLossesFromDeal(trans.deal);
}

//-------------------------------------------------------------------
// CREATE BUTTONS
//-------------------------------------------------------------------
void CreateControlButtons()
{
   ObjectDelete(0, "M1SCALPER_START");
   ObjectDelete(0, "M1SCALPER_STOP");

   ObjectCreate(0,
                "M1SCALPER_START",
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    "M1SCALPER_START",
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    "M1SCALPER_START",
                    OBJPROP_XDISTANCE,
                    10);

   ObjectSetInteger(0,
                    "M1SCALPER_START",
                    OBJPROP_YDISTANCE,
                    20);

   ObjectSetInteger(0,
                    "M1SCALPER_START",
                    OBJPROP_XSIZE,
                    90);

   ObjectSetInteger(0,
                    "M1SCALPER_START",
                    OBJPROP_YSIZE,
                    30);

   ObjectSetString(0,
                   "M1SCALPER_START",
                   OBJPROP_TEXT,
                   "START");


   ObjectCreate(0,
                "M1SCALPER_STOP",
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_XDISTANCE,
                    110);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_YDISTANCE,
                    20);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_XSIZE,
                    90);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_YSIZE,
                    30);

   ObjectSetString(0,
                   "M1SCALPER_STOP",
                   OBJPROP_TEXT,
                   "STOP");
}

//-------------------------------------------------------------------
// UPDATE STATUS
//-------------------------------------------------------------------
void UpdateStatus()
{
   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   string runText = TradingEnabled ? "RUNNING" : "STOPPED";

   Comment(
      "M1 TREND CONTINUATION SCALPER v6\n",
      "Status: ", runText, "\n",
      "Trend: ", trendText, "\n",
      "TP/SL Ratio: ", DoubleToString(TakeProfitRiskRatio, 2), "\n",
      "Open Positions: ", CountOpenPositions(), "\n",
      "Exposure Lots: ", DoubleToString(GetCurrentExposureLots(), 2), "\n",
      "Consecutive Losses: ", ConsecutiveLosses
   );
}//+------------------------------------------------------------------+
//| DAILY / RISK PROTECTION                                          |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// RESET DAILY STATISTICS
//-------------------------------------------------------------------
void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   int currentDayKey =
      tm.year * 10000 +
      tm.mon  * 100 +
      tm.day;

   if(LastTradingDayKey != currentDayKey)
   {
      LastTradingDayKey = currentDayKey;

      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      PeakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);

      ConsecutiveLosses = 0;
   }
}

//-------------------------------------------------------------------
// UPDATE PEAK EQUITY
//-------------------------------------------------------------------
void UpdatePeakEquity()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > PeakEquity)
      PeakEquity = equity;
}

//-------------------------------------------------------------------
// DAILY LOSS PROTECTION
//-------------------------------------------------------------------
bool DailyLossProtection()
{
   if(DailyLossLimitPercent <= 0.0)
      return false;

   if(DayStartBalance <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double lossPercent =
      ((DayStartBalance - equity) / DayStartBalance) * 100.0;

   if(lossPercent >= DailyLossLimitPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// DRAWDOWN PROTECTION
//-------------------------------------------------------------------
bool DrawdownProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return false;

   if(PeakEquity <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double drawdownPercent =
      ((PeakEquity - equity) / PeakEquity) * 100.0;

   if(drawdownPercent >= MaximumDrawdownPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// CONSECUTIVE LOSS PROTECTION
//-------------------------------------------------------------------
bool ConsecutiveLossProtection()
{
   if(MaximumConsecutiveLosses <= 0)
      return false;

   if(ConsecutiveLosses >= MaximumConsecutiveLosses)
      return true;

   return false;
}

//-------------------------------------------------------------------
// CAN TRADE
//-------------------------------------------------------------------
bool CanTrade()
{
   if(!TradingEnabled)
      return false;

   if(DailyLossProtection())
      return false;

   if(DrawdownProtection())
      return false;

   if(ConsecutiveLossProtection())
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| M1 DATA                                                          |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// ENOUGH BARS
//-------------------------------------------------------------------
bool EnoughM1Bars()
{
   int requiredBars =
      MathMax(
         StructureLookback,
         MathMax(
            ContinuationLookback,
            ReverseBreakoutLookback
         )
      ) + 10;

   int bars = Bars(_Symbol, PERIOD_M1);

   if(bars < requiredBars)
      return false;

   return true;
}

//-------------------------------------------------------------------
// HIGHEST HIGH
//-------------------------------------------------------------------
double GetHighestHigh(int startShift, int count)
{
   double highest = -DBL_MAX;

   for(int i = startShift; i < startShift + count; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M1, i);

      if(high > highest)
         highest = high;
   }

   return highest;
}

//-------------------------------------------------------------------
// LOWEST LOW
//-------------------------------------------------------------------
double GetLowestLow(int startShift, int count)
{
   double lowest = DBL_MAX;

   for(int i = startShift; i < startShift + count; i++)
   {
      double low = iLow(_Symbol, PERIOD_M1, i);

      if(low < lowest)
         lowest = low;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| STRUCTURE                                                        |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// BULLISH STRUCTURE
//-------------------------------------------------------------------
bool IsBullishStructure()
{
   double high1 = iHigh(_Symbol, PERIOD_M1, 1);
   double high2 = iHigh(_Symbol, PERIOD_M1, 2);

   double low1 = iLow(_Symbol, PERIOD_M1, 1);
   double low2 = iLow(_Symbol, PERIOD_M1, 2);

   if(high1 > high2 && low1 > low2)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH STRUCTURE
//-------------------------------------------------------------------
bool IsBearishStructure()
{
   double high1 = iHigh(_Symbol, PERIOD_M1, 1);
   double high2 = iHigh(_Symbol, PERIOD_M1, 2);

   double low1 = iLow(_Symbol, PERIOD_M1, 1);
   double low2 = iLow(_Symbol, PERIOD_M1, 2);

   if(high1 < high2 && low1 < low2)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CURRENT M1 MOMENTUM                                              |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// BULLISH MOMENTUM
//-------------------------------------------------------------------
bool BullishMomentum()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double openPrice = iOpen(_Symbol, PERIOD_M1, 0);
   double highPrice = iHigh(_Symbol, PERIOD_M1, 0);
   double lowPrice  = iLow(_Symbol, PERIOD_M1, 0);

   double range = highPrice - lowPrice;

   if(range <= 0.0)
      return false;

   double body = MathAbs(tick.bid - openPrice);

   double bodyPercent =
      (body / range) * 100.0;

   if(tick.bid > openPrice &&
      bodyPercent >= MinimumBodyPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH MOMENTUM
//-------------------------------------------------------------------
bool BearishMomentum()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double openPrice = iOpen(_Symbol, PERIOD_M1, 0);
   double highPrice = iHigh(_Symbol, PERIOD_M1, 0);
   double lowPrice  = iLow(_Symbol, PERIOD_M1, 0);

   double range = highPrice - lowPrice;

   if(range <= 0.0)
      return false;

   double body = MathAbs(tick.bid - openPrice);

   double bodyPercent =
      (body / range) * 100.0;

   if(tick.bid < openPrice &&
      bodyPercent >= MinimumBodyPercent)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CONTINUATION BREAKOUT                                            |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// BULLISH CONTINUATION BREAKOUT
//-------------------------------------------------------------------
bool BullishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double previousHigh =
      GetHighestHigh(1, ContinuationLookback);

   if(tick.ask > previousHigh)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH CONTINUATION BREAKOUT
//-------------------------------------------------------------------
bool BearishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double previousLow =
      GetLowestLow(1, ContinuationLookback);

   if(tick.bid < previousLow)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| REVERSE BREAKOUT                                                 |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// BULLISH TREND -> BEARISH REVERSAL
//-------------------------------------------------------------------
bool BullishReverseBreakout()
{
   if(CurrentTrend != TREND_BUY)
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double previousLow =
      GetLowestLow(1, ReverseBreakoutLookback);

   if(tick.bid < previousLow)
   {
      if(BearishMomentum())
         return true;
   }

   return false;
}

//-------------------------------------------------------------------
// BEARISH TREND -> BULLISH REVERSAL
//-------------------------------------------------------------------
bool BearishReverseBreakout()
{
   if(CurrentTrend != TREND_SELL)
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double previousHigh =
      GetHighestHigh(1, ReverseBreakoutLookback);

   if(tick.ask > previousHigh)
   {
      if(BullishMomentum())
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| TREND DETECTION                                                  |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// INITIAL TREND
//-------------------------------------------------------------------
int DetectInitialTrend()
{
   bool bullishStructure = IsBullishStructure();
   bool bearishStructure = IsBearishStructure();

   bool bullishMomentum = BullishMomentum();
   bool bearishMomentum = BearishMomentum();

   if(bullishStructure && bullishMomentum)
      return TREND_BUY;

   if(bearishStructure && bearishMomentum)
      return TREND_SELL;

   return TREND_NONE;
}

//-------------------------------------------------------------------
// UPDATE TREND STATE
//-------------------------------------------------------------------
void UpdateTrendState()
{
   if(CurrentTrend == TREND_NONE)
   {
      CurrentTrend = DetectInitialTrend();
      return;
   }

   // Existing BUY trend stays BUY until a genuine bearish
   // reverse breakout with bearish momentum occurs.
   if(CurrentTrend == TREND_BUY)
   {
      if(BullishReverseBreakout())
         CurrentTrend = TREND_SELL;

      return;
   }

   // Existing SELL trend stays SELL until a genuine bullish
   // reverse breakout with bullish momentum occurs.
   if(CurrentTrend == TREND_SELL)
   {
      if(BearishReverseBreakout())
         CurrentTrend = TREND_BUY;

      return;
   }
}//+------------------------------------------------------------------+
//| SCORING                                                          |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// BUY SCORE
//-------------------------------------------------------------------
double GetBuyScore()
{
   if(CurrentTrend != TREND_BUY)
      return 0.0;

   double score = 0.0;

   if(IsBullishStructure())
      score += 25.0;

   if(BullishMomentum())
      score += 30.0;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return score;

   double currentOpen =
      iOpen(_Symbol, PERIOD_M1, 0);

   if(tick.bid > currentOpen)
      score += 20.0;

   if(BullishContinuationBreakout())
      score += 25.0;

   return score;
}

//-------------------------------------------------------------------
// SELL SCORE
//-------------------------------------------------------------------
double GetSellScore()
{
   if(CurrentTrend != TREND_SELL)
      return 0.0;

   double score = 0.0;

   if(IsBearishStructure())
      score += 25.0;

   if(BearishMomentum())
      score += 30.0;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return score;

   double currentOpen =
      iOpen(_Symbol, PERIOD_M1, 0);

   if(tick.bid < currentOpen)
      score += 20.0;

   if(BearishContinuationBreakout())
      score += 25.0;

   return score;
}

//+------------------------------------------------------------------+
//| POSITION / LOT MANAGEMENT                                        |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// NORMALIZE VOLUME
//-------------------------------------------------------------------
double NormalizeVolume(double volume)
{
   double minLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = minLot;

   if(volume < minLot)
      volume = minLot;

   if(volume > maxLot)
      volume = maxLot;

   if(volume > MaximumLotSize)
      volume = MaximumLotSize;

   volume =
      MathFloor(volume / step) * step;

   int digits = 2;

   if(step < 0.01)
      digits = 3;

   if(step < 0.001)
      digits = 4;

   return NormalizeDouble(volume, digits);
}

//-------------------------------------------------------------------
// DYNAMIC LOT SIZE
//-------------------------------------------------------------------
double CalculateLotSize()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double lot =
      balance * LotMultiplier;

   return NormalizeVolume(lot);
}

//-------------------------------------------------------------------
// COUNT EA POSITIONS
//-------------------------------------------------------------------
int CountOpenPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      if(magic == (long)MagicNumber &&
         symbol == _Symbol)
      {
         count++;
      }
   }

   return count;
}

//-------------------------------------------------------------------
// CURRENT EA EXPOSURE
//-------------------------------------------------------------------
double GetCurrentExposureLots()
{
   double totalLots = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      if(magic == (long)MagicNumber &&
         symbol == _Symbol)
      {
         totalLots +=
            PositionGetDouble(POSITION_VOLUME);
      }
   }

   return totalLots;
}

//+------------------------------------------------------------------+
//| ENTRY CONTROL                                                    |
//+------------------------------------------------------------------+

//-------------------------------------------------------------------
// CHECK FOR ENTRY
//-------------------------------------------------------------------
void CheckForEntry()
{
   if(!CanTrade())
      return;

   if(CountOpenPositions() >= MaximumOpenPositions)
      return;

   double lot = CalculateLotSize();

   if(lot <= 0.0)
      return;

   if(MaximumEAExposureLots > 0.0)
   {
      double currentExposure =
         GetCurrentExposureLots();

      if(currentExposure + lot >
         MaximumEAExposureLots)
      {
         return;
      }
   }

   if(CurrentTrend == TREND_BUY)
   {
      double buyScore = GetBuyScore();

      if(buyScore >= SignalThreshold)
         OpenBuy();

      return;
   }

   if(CurrentTrend == TREND_SELL)
   {
      double sellScore = GetSellScore();

      if(sellScore >= SignalThreshold)
         OpenSell();

      return;
   }
}

//+------------------------------------------------------------------+
//| OPEN BUY                                                         |
//+------------------------------------------------------------------+
bool OpenBuy()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double lot = CalculateLotSize();

   if(lot <= 0.0)
      return false;

   double swingLow =
      GetLowestLow(1, StructureLookback);

   if(swingLow <= 0.0)
      return false;

   // Structure-based SL.
   double sl =
      swingLow -
      (SLBufferPoints * _Point);

   double entry =
      tick.ask;

   double riskDistance =
      entry - sl;

   if(riskDistance <= 0.0)
      return false;

   // Broker minimum stop distance.
   long stopsLevel =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_STOPS_LEVEL);

   double minimumDistance =
      stopsLevel * _Point;

   if(riskDistance < minimumDistance)
   {
      sl =
         entry - minimumDistance;

      riskDistance =
         entry - sl;
   }

   // TP deliberately closer than SL.
   double tp =
      entry +
      (riskDistance * TakeProfitRiskRatio);

   // Make sure TP also respects broker minimum.
   if((tp - entry) < minimumDistance)
      tp = entry + minimumDistance;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M1 Trend BUY"
      );

   return result;
}

//+------------------------------------------------------------------+
//| OPEN SELL                                                        |
//+------------------------------------------------------------------+
bool OpenSell()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double lot = CalculateLotSize();

   if(lot <= 0.0)
      return false;

   double swingHigh =
      GetHighestHigh(1, StructureLookback);

   if(swingHigh <= 0.0)
      return false;

   // Structure-based SL.
   double sl =
      swingHigh +
      (SLBufferPoints * _Point);

   double entry =
      tick.bid;

   double riskDistance =
      sl - entry;

   if(riskDistance <= 0.0)
      return false;

   // Broker minimum stop distance.
   long stopsLevel =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_STOPS_LEVEL);

   double minimumDistance =
      stopsLevel * _Point;

   if(riskDistance < minimumDistance)
   {
      sl =
         entry + minimumDistance;

      riskDistance =
         sl - entry;
   }

   // TP deliberately closer than SL.
   double tp =
      entry -
      (riskDistance * TakeProfitRiskRatio);

   // Make sure TP also respects broker minimum.
   if((entry - tp) < minimumDistance)
      tp = entry - minimumDistance;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M1 Trend SELL"
      );

   return result;
}

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS TRACKING                                        |
//+------------------------------------------------------------------+
void UpdateConsecutiveLossesFromDeal(ulong dealTicket)
{
   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   string symbol =
      HistoryDealGetString(
         dealTicket,
         DEAL_SYMBOL
      );

   long magic =
      HistoryDealGetInteger(
         dealTicket,
         DEAL_MAGIC
      );

   long entryType =
      HistoryDealGetInteger(
         dealTicket,
         DEAL_ENTRY
      );

   if(symbol != _Symbol)
      return;

   if(magic != (long)MagicNumber)
      return;

   // Only process closing deals.
   if(entryType != DEAL_ENTRY_OUT &&
      entryType != DEAL_ENTRY_OUT_BY)
      return;

   double profit =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_PROFIT
      );

   double swap =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_SWAP
      );

   double commission =
      HistoryDealGetDouble(
         dealTicket,
         DEAL_COMMISSION
      );

   double netResult =
      profit +
      swap +
      commission;

   if(netResult < 0.0)
   {
      ConsecutiveLosses++;
   }
   else
   if(netResult > 0.0)
   {
      ConsecutiveLosses = 0;
   }
}
//+------------------------------------------------------------------+
