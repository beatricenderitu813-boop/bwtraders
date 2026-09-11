//+------------------------------------------------------------------+
//| M1 TREND CONTINUATION PROFIT RETRACE - v7.1                     |
//| M1 scalping EA with profit-retrace protection and Expert logs    |
//+------------------------------------------------------------------+
#property strict
#property version   "7.10"
#property description "M1 Trend Continuation EA - Profit Retrace Protection - Expert Logs"

#include <Trade/Trade.mqh>

CTrade trade;

//-------------------------------------------------------------------
// ENUMS
//-------------------------------------------------------------------
enum TrendDirection
{
   TREND_NONE = 0,
   TREND_BUY  = 1,
   TREND_SELL = -1
};

//-------------------------------------------------------------------
// GENERAL SETTINGS
//-------------------------------------------------------------------
input bool   StartTradingOnAttach = false;
input long   MagicNumber          = 26092027;

//-------------------------------------------------------------------
// SIGNAL SETTINGS
//-------------------------------------------------------------------
input double SignalThreshold = 70.0;

//-------------------------------------------------------------------
// LOT SETTINGS
//-------------------------------------------------------------------
input double LotMultiplier  = 0.001;
input double MaximumLotSize = 10.0;

//-------------------------------------------------------------------
// MARKET STRUCTURE SETTINGS
//-------------------------------------------------------------------
input int    StructureLookback       = 5;
input int    ContinuationLookback    = 5;
input int    ReverseBreakoutLookback = 5;
input double MinimumBodyPercent      = 50.0;

//-------------------------------------------------------------------
// PROFIT PROTECTION
//-------------------------------------------------------------------
input double ProfitProtectionStart = 1.00;
input double ProfitRetraceAmount   = 0.50;

//-------------------------------------------------------------------
// POSITION LIMITS
//-------------------------------------------------------------------
input int    MaximumOpenPositions  = 1;
input double MaximumEAExposureLots = 10.0;

//-------------------------------------------------------------------
// ACCOUNT PROTECTION
//-------------------------------------------------------------------
input double DailyLossLimitPercent = 2.0;

// IMPORTANT:
// Drawdown is calculated from the START-OF-DAY BALANCE.
// A profitable equity peak does NOT become a new drawdown reference.
input double MaximumDrawdownPercent = 5.0;

input int MaximumConsecutiveLosses = 3;

//-------------------------------------------------------------------
// TRADE SETTINGS
//-------------------------------------------------------------------
input int SlippagePoints = 20;

//-------------------------------------------------------------------
// EXPERT LOGGING
//-------------------------------------------------------------------
input bool EnableExpertLogs = true;
input int  ExpertLogIntervalSeconds = 3;

//-------------------------------------------------------------------
// GLOBAL VARIABLES
//-------------------------------------------------------------------
bool TradingEnabled = false;

int CurrentTrend = TREND_NONE;

double DayStartBalance = 0.0;
double PeakEquity      = 0.0;

int ConsecutiveLosses = 0;

int LastTradingDayKey = 0;

//-------------------------------------------------------------------
// PROFIT PROTECTION STATE
//-------------------------------------------------------------------
bool   ProfitProtectionActive = false;
double PeakPositionProfit     = 0.0;
ulong  TrackedPositionTicket  = 0;

//-------------------------------------------------------------------
// LOGGING STATE
//-------------------------------------------------------------------
datetime LastExpertLogTime = 0;
string   LastExpertState   = "";

//-------------------------------------------------------------------
// FUNCTION DECLARATIONS
//-------------------------------------------------------------------
void CreateControlButtons();
void UpdateStatus();

void ResetDailyStatisticsIfNeeded();
void UpdatePeakEquity();

bool CanTrade();
bool DailyLossProtection();
bool DrawdownProtection();
bool ConsecutiveLossProtection();

bool EnoughM1Bars();

double CalculateLotSize();
double NormalizeVolume(double volume);

int    CountOpenPositions();
double GetCurrentExposureLots();

double GetHighestHigh(int startShift, int count);
double GetLowestLow(int startShift, int count);

bool IsBullishStructure();
bool IsBearishStructure();

bool BullishMomentum();
bool BearishMomentum();

bool BullishContinuationBreakout();
bool BearishContinuationBreakout();

bool BullishReverseBreakout();
bool BearishReverseBreakout();

int DetectInitialTrend();
void UpdateTrendState();

double GetBuyScore();
double GetSellScore();

void CheckForEntry();

bool OpenBuy();
bool OpenSell();

void ManageProfitRetrace();

bool FindTrackedPosition(ulong &ticket,
                         double &profit,
                         long &positionType);

void ResetProfitTracker();

void LogExpertStatus();
void LogEntryBlockReason();

void UpdateConsecutiveLossesFromDeal(ulong dealTicket);

//-------------------------------------------------------------------
// ON INIT
//-------------------------------------------------------------------
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   DayStartBalance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   PeakEquity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   LastTradingDayKey = 0;

   ConsecutiveLosses = 0;

   CurrentTrend = TREND_NONE;

   ProfitProtectionActive = false;
   PeakPositionProfit     = 0.0;
   TrackedPositionTicket  = 0;

   TradingEnabled =
      StartTradingOnAttach;

   if(EnableExpertLogs)
   {
      Print("M1 SCALPER: EA INITIALIZED | Symbol=",
            _Symbol,
            " | M1 | Trading=",
            (TradingEnabled ? "RUNNING" : "STOPPED"),
            " | Threshold=",
            DoubleToString(SignalThreshold,1),
            "%");
   }

   CreateControlButtons();
   UpdateStatus();

   return(INIT_SUCCEEDED);
}

//-------------------------------------------------------------------
// ON DEINIT
//-------------------------------------------------------------------
void OnDeinit(const int reason)
{
   ObjectDelete(0,
                "M1SCALPER_START");

   ObjectDelete(0,
                "M1SCALPER_STOP");

   Comment("");
}

//-------------------------------------------------------------------
// ON TICK
//-------------------------------------------------------------------
void OnTick()
{
   ResetDailyStatisticsIfNeeded();

   UpdatePeakEquity();

   // Profit protection remains active even when START is OFF.
   ManageProfitRetrace();

   if(!EnoughM1Bars())
   {
      UpdateStatus();
      return;
   }

   UpdateTrendState();

   UpdateStatus();

   if(!TradingEnabled)
   {
      LogEntryBlockReason();
      return;
   }

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

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: START PRESSED | Trading enabled | Symbol=",
               _Symbol);
      }

      ObjectSetInteger(0,
                       "M1SCALPER_START",
                       OBJPROP_STATE,
                       false);

      UpdateStatus();
   }

   if(sparam == "M1SCALPER_STOP")
   {
      TradingEnabled = false;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: STOP PRESSED | New entries disabled");
      }

      ObjectSetInteger(0,
                       "M1SCALPER_STOP",
                       OBJPROP_STATE,
                       false);

      UpdateStatus();
   }

   ChartRedraw();
}

//-------------------------------------------------------------------
// TRADE TRANSACTION
//-------------------------------------------------------------------
void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;

   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   long magic =
      HistoryDealGetInteger(dealTicket,
                            DEAL_MAGIC);

   if(magic != MagicNumber)
      return;

   if(EnableExpertLogs)
   {
      long dealType =
         HistoryDealGetInteger(dealTicket,
                               DEAL_TYPE);

      double dealVolume =
         HistoryDealGetDouble(dealTicket,
                              DEAL_VOLUME);

      double dealPrice =
         HistoryDealGetDouble(dealTicket,
                              DEAL_PRICE);

      double dealProfit =
         HistoryDealGetDouble(dealTicket,
                              DEAL_PROFIT);

      Print("M1 SCALPER: DEAL EVENT | Ticket=",
            dealTicket,
            " | Type=",
            dealType,
            " | Volume=",
            DoubleToString(dealVolume,2),
            " | Price=",
            DoubleToString(dealPrice,_Digits),
            " | Profit=",
            DoubleToString(dealProfit,2));
   }

   UpdateConsecutiveLossesFromDeal(dealTicket);
}

//-------------------------------------------------------------------
// CREATE START/STOP BUTTONS
//-------------------------------------------------------------------
void CreateControlButtons()
{
   ObjectDelete(0,
                "M1SCALPER_START");

   ObjectDelete(0,
                "M1SCALPER_STOP");

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
                    100);

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
                    120);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_YDISTANCE,
                    20);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_XSIZE,
                    100);

   ObjectSetInteger(0,
                    "M1SCALPER_STOP",
                    OBJPROP_YSIZE,
                    30);

   ObjectSetString(0,
                   "M1SCALPER_STOP",
                   OBJPROP_TEXT,
                   "STOP");

   ChartRedraw();
}

//-------------------------------------------------------------------
// UPDATE CHART STATUS
//-------------------------------------------------------------------
void UpdateStatus()
{
   string tradingState =
      TradingEnabled ? "RUNNING" : "STOPPED";

   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   int openPositions =
      CountOpenPositions();

   double exposure =
      GetCurrentExposureLots();

   string protectionText =
      ProfitProtectionActive ? "ACTIVE" : "WAITING";

   Comment(
      "M1 SCALPER\n",
      "Status: ", tradingState, "\n",
      "Symbol: ", _Symbol, "\n",
      "Timeframe: M1\n",
      "Trend: ", trendText, "\n",
      "Profit Protection: ", protectionText, "\n",
      "Peak Profit: $",
      DoubleToString(PeakPositionProfit,2), "\n",
      "Retrace Amount: $",
      DoubleToString(ProfitRetraceAmount,2), "\n",
      "Open Positions: ",
      IntegerToString(openPositions), "\n",
      "Exposure Lots: ",
      DoubleToString(exposure,2), "\n",
      "Consecutive Losses: ",
      IntegerToString(ConsecutiveLosses)
   );
}

//-------------------------------------------------------------------
// RESET DAILY STATISTICS
//-------------------------------------------------------------------
void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime tm;

   TimeToStruct(TimeCurrent(),
                tm);

   int dayKey =
      tm.year * 10000 +
      tm.mon  * 100 +
      tm.day;

   if(dayKey != LastTradingDayKey)
   {
      LastTradingDayKey = dayKey;

      DayStartBalance =
         AccountInfoDouble(ACCOUNT_BALANCE);

      PeakEquity =
         AccountInfoDouble(ACCOUNT_EQUITY);

      ConsecutiveLosses = 0;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: NEW TRADING DAY | Start Balance=",
               DoubleToString(DayStartBalance,2));
      }
   }
}

//-------------------------------------------------------------------
// UPDATE PEAK EQUITY
//-------------------------------------------------------------------
void UpdatePeakEquity()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

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

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   double lossPercent =
      ((DayStartBalance - equity) /
       DayStartBalance) * 100.0;

   if(lossPercent >= DailyLossLimitPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// DRAWDOWN PROTECTION
// IMPORTANT:
// Uses START-OF-DAY BALANCE.
// It does NOT use PeakEquity.
//-------------------------------------------------------------------
bool DrawdownProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return false;

   if(DayStartBalance <= 0.0)
      return false;

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   double drawdownPercent =
      ((DayStartBalance - equity) /
       DayStartBalance) * 100.0;

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

   if(ConsecutiveLosses >=
      MaximumConsecutiveLosses)
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

//-------------------------------------------------------------------
// ENOUGH M1 BARS
//-------------------------------------------------------------------
bool EnoughM1Bars()
{
   int bars =
      Bars(_Symbol,
           PERIOD_M1);

   int minimumBars =
      MathMax(
         StructureLookback,
         MathMax(
            ContinuationLookback,
            ReverseBreakoutLookback
         )
      ) + 10;

   if(bars < minimumBars)
      return false;

   return true;
}

//-------------------------------------------------------------------
// CALCULATE LOT SIZE
//-------------------------------------------------------------------
double CalculateLotSize()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double lot =
      balance * LotMultiplier;

   if(lot <= 0.0)
      return 0.0;

   if(lot > MaximumLotSize)
      lot = MaximumLotSize;

   return NormalizeVolume(lot);
}

//-------------------------------------------------------------------
// NORMALIZE VOLUME
//-------------------------------------------------------------------
double NormalizeVolume(double volume)
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

   if(step <= 0.0)
      step = minLot;

   if(volume < minLot)
      volume = minLot;

   if(volume > maxLot)
      volume = maxLot;

   volume =
      MathFloor(volume / step) * step;

   int volumeDigits = 2;

   if(step == 1.0)
      volumeDigits = 0;
   else if(step == 0.1)
      volumeDigits = 1;
   else if(step == 0.01)
      volumeDigits = 2;
   else if(step == 0.001)
      volumeDigits = 3;

   return NormalizeDouble(volume,
                          volumeDigits);
}//-------------------------------------------------------------------
// COUNT OPEN POSITIONS
//-------------------------------------------------------------------
int CountOpenPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol)
         continue;

      if(magic != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//-------------------------------------------------------------------
// CURRENT EA EXPOSURE
//-------------------------------------------------------------------
double GetCurrentExposureLots()
{
   double exposure = 0.0;

   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol)
         continue;

      if(magic != MagicNumber)
         continue;

      exposure +=
         PositionGetDouble(POSITION_VOLUME);
   }

   return exposure;
}

//-------------------------------------------------------------------
// HIGHEST HIGH
//-------------------------------------------------------------------
double GetHighestHigh(int startShift,
                      int count)
{
   double highest = -DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double high =
         iHigh(_Symbol,
               PERIOD_M1,
               i);

      if(high > highest)
         highest = high;
   }

   return highest;
}

//-------------------------------------------------------------------
// LOWEST LOW
//-------------------------------------------------------------------
double GetLowestLow(int startShift,
                    int count)
{
   double lowest = DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double low =
         iLow(_Symbol,
              PERIOD_M1,
              i);

      if(low < lowest)
         lowest = low;
   }

   return lowest;
}

//-------------------------------------------------------------------
// BULLISH STRUCTURE
//-------------------------------------------------------------------
bool IsBullishStructure()
{
   double recentHigh =
      GetHighestHigh(1,
                     StructureLookback);

   double previousHigh =
      GetHighestHigh(StructureLookback + 1,
                     StructureLookback);

   double recentLow =
      GetLowestLow(1,
                   StructureLookback);

   double previousLow =
      GetLowestLow(StructureLookback + 1,
                   StructureLookback);

   if(recentHigh > previousHigh &&
      recentLow > previousLow)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH STRUCTURE
//-------------------------------------------------------------------
bool IsBearishStructure()
{
   double recentHigh =
      GetHighestHigh(1,
                     StructureLookback);

   double previousHigh =
      GetHighestHigh(StructureLookback + 1,
                     StructureLookback);

   double recentLow =
      GetLowestLow(1,
                   StructureLookback);

   double previousLow =
      GetLowestLow(StructureLookback + 1,
                   StructureLookback);

   if(recentHigh < previousHigh &&
      recentLow < previousLow)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BULLISH MOMENTUM
//-------------------------------------------------------------------
bool BullishMomentum()
{
   double openPrice =
      iOpen(_Symbol,
            PERIOD_M1,
            0);

   double currentPrice =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(openPrice <= 0.0 ||
      currentPrice <= 0.0)
      return false;

   double high =
      iHigh(_Symbol,
            PERIOD_M1,
            0);

   double low =
      iLow(_Symbol,
           PERIOD_M1,
           0);

   double range =
      high - low;

   if(range <= 0.0)
      return false;

   double body =
      MathAbs(currentPrice - openPrice);

   double bodyPercent =
      (body / range) * 100.0;

   if(currentPrice > openPrice &&
      bodyPercent >= MinimumBodyPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH MOMENTUM
//-------------------------------------------------------------------
bool BearishMomentum()
{
   double openPrice =
      iOpen(_Symbol,
            PERIOD_M1,
            0);

   double currentPrice =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(openPrice <= 0.0 ||
      currentPrice <= 0.0)
      return false;

   double high =
      iHigh(_Symbol,
            PERIOD_M1,
            0);

   double low =
      iLow(_Symbol,
           PERIOD_M1,
           0);

   double range =
      high - low;

   if(range <= 0.0)
      return false;

   double body =
      MathAbs(currentPrice - openPrice);

   double bodyPercent =
      (body / range) * 100.0;

   if(currentPrice < openPrice &&
      bodyPercent >= MinimumBodyPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BULLISH CONTINUATION BREAKOUT
//-------------------------------------------------------------------
bool BullishContinuationBreakout()
{
   double currentAsk =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   if(currentAsk <= 0.0)
      return false;

   double resistance =
      GetHighestHigh(1,
                     ContinuationLookback);

   if(currentAsk > resistance)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH CONTINUATION BREAKOUT
//-------------------------------------------------------------------
bool BearishContinuationBreakout()
{
   double currentBid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(currentBid <= 0.0)
      return false;

   double support =
      GetLowestLow(1,
                   ContinuationLookback);

   if(currentBid < support)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BULLISH REVERSE BREAKOUT
//-------------------------------------------------------------------
bool BullishReverseBreakout()
{
   double currentAsk =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   if(currentAsk <= 0.0)
      return false;

   double breakoutLevel =
      GetHighestHigh(1,
                     ReverseBreakoutLookback);

   if(currentAsk > breakoutLevel)
      return true;

   return false;
}

//-------------------------------------------------------------------
// BEARISH REVERSE BREAKOUT
//-------------------------------------------------------------------
bool BearishReverseBreakout()
{
   double currentBid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(currentBid <= 0.0)
      return false;

   double breakoutLevel =
      GetLowestLow(1,
                   ReverseBreakoutLookback);

   if(currentBid < breakoutLevel)
      return true;

   return false;
}

//-------------------------------------------------------------------
// DETECT INITIAL TREND
//-------------------------------------------------------------------
int DetectInitialTrend()
{
   bool bullishStructure =
      IsBullishStructure();

   bool bearishStructure =
      IsBearishStructure();

   bool bullishMomentum =
      BullishMomentum();

   bool bearishMomentum =
      BearishMomentum();

   if(bullishStructure &&
      bullishMomentum)
      return TREND_BUY;

   if(bearishStructure &&
      bearishMomentum)
      return TREND_SELL;

   return TREND_NONE;
}

//-------------------------------------------------------------------
// UPDATE TREND STATE
//-------------------------------------------------------------------
void UpdateTrendState()
{
   int detectedTrend =
      DetectInitialTrend();

   if(detectedTrend != TREND_NONE)
   {
      if(detectedTrend != CurrentTrend)
      {
         CurrentTrend = detectedTrend;

         if(EnableExpertLogs)
         {
            if(CurrentTrend == TREND_BUY)
            {
               Print("M1 SCALPER: TREND CHANGED -> BUY");
            }

            if(CurrentTrend == TREND_SELL)
            {
               Print("M1 SCALPER: TREND CHANGED -> SELL");
            }
         }
      }
   }

   // Live reversal detection.
   if(BullishReverseBreakout())
   {
      if(CurrentTrend != TREND_BUY)
      {
         CurrentTrend = TREND_BUY;

         if(EnableExpertLogs)
         {
            Print("M1 SCALPER: LIVE REVERSAL DETECTED -> BUY");
         }
      }
   }

   if(BearishReverseBreakout())
   {
      if(CurrentTrend != TREND_SELL)
      {
         CurrentTrend = TREND_SELL;

         if(EnableExpertLogs)
         {
            Print("M1 SCALPER: LIVE REVERSAL DETECTED -> SELL");
         }
      }
   }
}

//-------------------------------------------------------------------
// BUY SCORE
//-------------------------------------------------------------------
double GetBuyScore()
{
   double score = 0.0;

   if(IsBullishStructure())
      score += 30.0;

   if(BullishMomentum())
      score += 25.0;

   if(BullishContinuationBreakout())
      score += 25.0;

   if(BullishReverseBreakout())
      score += 20.0;

   if(score > 100.0)
      score = 100.0;

   return score;
}

//-------------------------------------------------------------------
// SELL SCORE
//-------------------------------------------------------------------
double GetSellScore()
{
   double score = 0.0;

   if(IsBearishStructure())
      score += 30.0;

   if(BearishMomentum())
      score += 25.0;

   if(BearishContinuationBreakout())
      score += 25.0;

   if(BearishReverseBreakout())
      score += 20.0;

   if(score > 100.0)
      score = 100.0;

   return score;
}

//-------------------------------------------------------------------
// CHECK FOR ENTRY
//-------------------------------------------------------------------
void CheckForEntry()
{
   if(!CanTrade())
   {
      LogEntryBlockReason();
      return;
   }

   int openPositions =
      CountOpenPositions();

   if(openPositions >= MaximumOpenPositions)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: ENTRY BLOCKED | Maximum open positions reached | Open=",
               openPositions,
               " | Max=",
               MaximumOpenPositions);
      }

      return;
   }

   double exposure =
      GetCurrentExposureLots();

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
   {
      if(EnableExpertLogs)
         Print("M1 SCALPER: ENTRY BLOCKED | Invalid lot size");

      return;
   }

   if(MaximumEAExposureLots > 0.0 &&
      exposure + lot > MaximumEAExposureLots)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: ENTRY BLOCKED | EA exposure limit | Current=",
               DoubleToString(exposure,2),
               " | New=",
               DoubleToString(lot,2),
               " | Maximum=",
               DoubleToString(MaximumEAExposureLots,2));
      }

      return;
   }

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   if(EnableExpertLogs)
   {
      Print("M1 SCALPER: SCANNING | BUY SCORE=",
            DoubleToString(buyScore,1),
            "% | SELL SCORE=",
            DoubleToString(sellScore,1),
            "% | Threshold=",
            DoubleToString(SignalThreshold,1),
            "%");
   }

   if(buyScore >= SignalThreshold &&
      buyScore > sellScore)
   {
      if(EnableExpertLogs)
         Print("M1 SCALPER: BUY CONFIRMED | Score=",
               DoubleToString(buyScore,1),
               "%");

      if(OpenBuy())
         return;
   }

   if(sellScore >= SignalThreshold &&
      sellScore > buyScore)
   {
      if(EnableExpertLogs)
         Print("M1 SCALPER: SELL CONFIRMED | Score=",
               DoubleToString(sellScore,1),
               "%");

      if(OpenSell())
         return;
   }

   if(EnableExpertLogs)
      Print("M1 SCALPER: WAITING | No confirmed entry");
}//-------------------------------------------------------------------
// OPEN BUY
//-------------------------------------------------------------------
bool OpenBuy()
{
   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
      return false;

   double ask =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   if(ask <= 0.0)
      return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   // No SL and no TP.
   bool result =
      trade.Buy(lot,
                _Symbol,
                0.0,
                0.0,
                0.0,
                "M1 Trend BUY");

   if(result)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE OPENED | BUY | Lot=",
               DoubleToString(lot,2),
               " | Price=",
               DoubleToString(ask,_Digits));
      }
   }
   else
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE FAILED | BUY | Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());
      }
   }

   return result;
}

//-------------------------------------------------------------------
// OPEN SELL
//-------------------------------------------------------------------
bool OpenSell()
{
   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
      return false;

   double bid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   // No SL and no TP.
   bool result =
      trade.Sell(lot,
                 _Symbol,
                 0.0,
                 0.0,
                 0.0,
                 "M1 Trend SELL");

   if(result)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE OPENED | SELL | Lot=",
               DoubleToString(lot,2),
               " | Price=",
               DoubleToString(bid,_Digits));
      }
   }
   else
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE FAILED | SELL | Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());
      }
   }

   return result;
}

//-------------------------------------------------------------------
// FIND TRACKED POSITION
//-------------------------------------------------------------------
bool FindTrackedPosition(ulong &ticket,
                          double &profit,
                          long &positionType)
{
   ticket = 0;
   profit = 0.0;
   positionType = -1;

   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong positionTicket =
         PositionGetTicket(i);

      if(positionTicket == 0)
         continue;

      if(!PositionSelectByTicket(positionTicket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol)
         continue;

      if(magic != MagicNumber)
         continue;

      ticket = positionTicket;

      profit =
         PositionGetDouble(POSITION_PROFIT);

      positionType =
         PositionGetInteger(POSITION_TYPE);

      return true;
   }

   return false;
}

//-------------------------------------------------------------------
// RESET PROFIT TRACKER
//-------------------------------------------------------------------
void ResetProfitTracker()
{
   ProfitProtectionActive = false;
   PeakPositionProfit     = 0.0;
   TrackedPositionTicket  = 0;
}

//-------------------------------------------------------------------
// MANAGE PROFIT RETRACE
//-------------------------------------------------------------------
void ManageProfitRetrace()
{
   ulong ticket = 0;
   double profit = 0.0;
   long positionType = -1;

   bool found =
      FindTrackedPosition(ticket,
                          profit,
                          positionType);

   if(!found)
   {
      if(TrackedPositionTicket != 0 ||
         ProfitProtectionActive)
      {
         if(EnableExpertLogs)
         {
            Print("M1 SCALPER: PROFIT TRACKER RESET | No EA position");
         }

         ResetProfitTracker();
      }

      return;
   }

   //----------------------------------------------------------------
   // Start tracking a new position.
   //----------------------------------------------------------------
   if(ticket != TrackedPositionTicket)
   {
      TrackedPositionTicket = ticket;

      PeakPositionProfit = profit;

      ProfitProtectionActive = false;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRACKING POSITION | Ticket=",
               ticket,
               " | Initial Profit=$",
               DoubleToString(profit,2));
      }
   }

   //----------------------------------------------------------------
   // Update the highest profit reached.
   //----------------------------------------------------------------
   if(profit > PeakPositionProfit)
      PeakPositionProfit = profit;

   //----------------------------------------------------------------
   // Activate protection after the required profit is reached.
   //----------------------------------------------------------------
   if(!ProfitProtectionActive &&
      PeakPositionProfit >= ProfitProtectionStart)
   {
      ProfitProtectionActive = true;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: PROFIT PROTECTION ACTIVE | Peak=$",
               DoubleToString(PeakPositionProfit,2),
               " | Retrace=$",
               DoubleToString(ProfitRetraceAmount,2));
      }
   }

   //----------------------------------------------------------------
   // Close when profit retraces by the configured amount.
   //----------------------------------------------------------------
   if(ProfitProtectionActive)
   {
      double protectionLevel =
         PeakPositionProfit -
         ProfitRetraceAmount;

      if(profit <= protectionLevel)
      {
         if(EnableExpertLogs)
         {
            Print("M1 SCALPER: PROFIT RETRACE TRIGGERED | Current=$",
                  DoubleToString(profit,2),
                  " | Peak=$",
                  DoubleToString(PeakPositionProfit,2),
                  " | Protection Level=$",
                  DoubleToString(protectionLevel,2),
                  " | Closing position");
         }

         bool closed =
            trade.PositionClose(ticket);

         if(closed)
         {
            if(EnableExpertLogs)
            {
               Print("M1 SCALPER: PROFIT PROTECTED | Ticket=",
                     ticket,
                     " | Closed at approximately $",
                     DoubleToString(profit,2));
            }
         }
         else
         {
            if(EnableExpertLogs)
            {
               Print("M1 SCALPER: CLOSE FAILED | Ticket=",
                     ticket,
                     " | Retcode=",
                     trade.ResultRetcode(),
                     " | ",
                     trade.ResultRetcodeDescription());
            }

            // Do not reset the tracker if closing failed.
            return;
         }

         ResetProfitTracker();
      }
   }
}

//-------------------------------------------------------------------
// LOG EXPERT STATUS
//-------------------------------------------------------------------
void LogExpertStatus()
{
   if(!EnableExpertLogs)
      return;

   datetime now =
      TimeCurrent();

   if(ExpertLogIntervalSeconds > 0)
   {
      if((now - LastExpertLogTime) <
         ExpertLogIntervalSeconds)
         return;
   }

   LastExpertLogTime = now;

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   string state =
      "SCANNING";

   if(!TradingEnabled)
      state = "STOPPED";
   else if(DailyLossProtection())
      state = "DAILY LOSS PROTECTION";
   else if(DrawdownProtection())
      state = "DRAWDOWN PROTECTION";
   else if(ConsecutiveLossProtection())
      state = "CONSECUTIVE LOSS PROTECTION";
   else if(CountOpenPositions() >= MaximumOpenPositions)
      state = "POSITION LIMIT";
   else if(buyScore < SignalThreshold &&
           sellScore < SignalThreshold)
      state = "WAITING";

   Print("M1 SCALPER: STATUS | State=",
         state,
         " | Trend=",
         trendText,
         " | BUY=",
         DoubleToString(buyScore,1),
         "% | SELL=",
         DoubleToString(sellScore,1),
         "% | Open=",
         CountOpenPositions(),
         " | ConsecutiveLosses=",
         ConsecutiveLosses);
}

//-------------------------------------------------------------------
// LOG ENTRY BLOCK REASON
//-------------------------------------------------------------------
void LogEntryBlockReason()
{
   if(!EnableExpertLogs)
      return;

   datetime now =
      TimeCurrent();

   if(ExpertLogIntervalSeconds > 0)
   {
      if((now - LastExpertLogTime) <
         ExpertLogIntervalSeconds)
         return;
   }

   LastExpertLogTime = now;

   if(!TradingEnabled)
   {
      Print("M1 SCALPER: WAITING | Trading is STOPPED | Press START to enable new entries");
      return;
   }

   if(DailyLossProtection())
   {
      Print("M1 SCALPER: ENTRY BLOCKED | Daily loss protection active | Limit=",
            DoubleToString(DailyLossLimitPercent,2),
            "%");
      return;
   }

   if(DrawdownProtection())
   {
      Print("M1 SCALPER: ENTRY BLOCKED | Drawdown protection active | Limit=",
            DoubleToString(MaximumDrawdownPercent,2),
            "% from start-of-day balance");
      return;
   }

   if(ConsecutiveLossProtection())
   {
      Print("M1 SCALPER: ENTRY BLOCKED | Consecutive loss protection active | Losses=",
            ConsecutiveLosses,
            " | Maximum=",
            MaximumConsecutiveLosses);
      return;
   }

   if(CountOpenPositions() >= MaximumOpenPositions)
   {
      Print("M1 SCALPER: WAITING | Existing EA position is open");
      return;
   }

   LogExpertStatus();
}

//-------------------------------------------------------------------
// UPDATE CONSECUTIVE LOSSES FROM DEAL
//-------------------------------------------------------------------
void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket)
{
   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   long dealEntry =
      HistoryDealGetInteger(dealTicket,
                            DEAL_ENTRY);

   // Only count deals that close a position.
   if(dealEntry != DEAL_ENTRY_OUT &&
      dealEntry != DEAL_ENTRY_OUT_BY)
      return;

   double profit =
      HistoryDealGetDouble(dealTicket,
                           DEAL_PROFIT);

   double swap =
      HistoryDealGetDouble(dealTicket,
                           DEAL_SWAP);

   double commission =
      HistoryDealGetDouble(dealTicket,
                           DEAL_COMMISSION);

   double netResult =
      profit +
      swap +
      commission;

   if(netResult < 0.0)
   {
      ConsecutiveLosses++;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: LOSS RECORDED | Net=$",
               DoubleToString(netResult,2),
               " | Consecutive Losses=",
               ConsecutiveLosses);
      }
   }
   else if(netResult > 0.0)
   {
      ConsecutiveLosses = 0;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: PROFIT RECORDED | Net=$",
               DoubleToString(netResult,2),
               " | Consecutive Losses RESET");
      }
   }
}

//-------------------------------------------------------------------
// END OF EA
//-------------------------------------------------------------------
