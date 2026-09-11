//+------------------------------------------------------------------+
//| M1 TREND CONTINUATION PROFIT RETRACE - v8.0                     |
//| Risk Controlled M1 Scalper                                      |
//+------------------------------------------------------------------+
#property strict
#property version   "8.00"
#property description "M1 Trend Continuation EA - Risk Controlled"

#include <Trade/Trade.mqh>

CTrade trade;

enum TrendDirection
{
   TREND_NONE = 0,
   TREND_BUY  = 1,
   TREND_SELL = -1
};

input bool   StartTradingOnAttach = false;
input long   MagicNumber          = 26092027;

input double SignalThreshold = 70.0;

input double LotMultiplier  = 0.001;
input double MaximumLotSize = 10.0;

// NEW: maximum risk allowed on one trade
input double MaximumRiskPercentPerTrade = 0.50;

input int    StructureLookback       = 5;
input int    ContinuationLookback    = 5;
input int    ReverseBreakoutLookback = 5;
input double MinimumBodyPercent      = 50.0;

// EXISTING PROFIT PROTECTION
input double ProfitProtectionStart = 1.00;
input double ProfitRetraceAmount   = 0.50;

// ADDITIONAL PROFIT PROTECTION
input double ProfitRetracePercent  = 50.0;

input int    MaximumOpenPositions  = 1;
input double MaximumEAExposureLots = 10.0;

input double DailyLossLimitPercent  = 2.0;
input double MaximumDrawdownPercent = 5.0;
input int    MaximumConsecutiveLosses = 3;

input int SlippagePoints = 20;

input bool EnableExpertLogs = true;
input int  ExpertLogIntervalSeconds = 3;

bool TradingEnabled = false;
int CurrentTrend = TREND_NONE;

double DayStartBalance = 0.0;
double PeakEquity = 0.0;

int ConsecutiveLosses = 0;
int LastTradingDayKey = 0;

bool   ProfitProtectionActive = false;
double PeakPositionProfit     = 0.0;
ulong  TrackedPositionTicket  = 0;

datetime LastExpertLogTime = 0;

// Function declarations
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

bool CalculateSafeStopLoss(
   ENUM_ORDER_TYPE orderType,
   double volume,
   double entryPrice,
   double &stopLoss);

double CalculateRiskMoney();

void ManageProfitRetrace();

bool FindTrackedPosition(
   ulong &ticket,
   double &profit,
   long &positionType);

void ResetProfitTracker();

void LogExpertStatus();
void LogEntryBlockReason();

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket);

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
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
      Print("M1 SCALPER v8.0: EA INITIALIZED | Symbol=",
            _Symbol,
            " | M1 | Trading=",
            (TradingEnabled ? "RUNNING" : "STOPPED"));

      Print("M1 SCALPER v8.0: ENTRY THRESHOLD=",
            DoubleToString(SignalThreshold,1),
            "% | MAX RISK PER TRADE=",
            DoubleToString(MaximumRiskPercentPerTrade,2),
            "%");

      Print("M1 SCALPER v8.0: PROFIT PROTECTION | Fixed=$",
            DoubleToString(ProfitRetraceAmount,2),
            " | Percentage=",
            DoubleToString(ProfitRetracePercent,1),
            "%");
   }

   CreateControlButtons();
   UpdateStatus();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0,
                "M1SCALPER_START");

   ObjectDelete(0,
                "M1SCALPER_STOP");

   Comment("");
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyStatisticsIfNeeded();
   UpdatePeakEquity();

   // Profit protection continues even when START is OFF.
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

//+------------------------------------------------------------------+
//| CHART BUTTONS                                                    |
//+------------------------------------------------------------------+
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
         Print("M1 SCALPER: START PRESSED | New entries ENABLED");
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
         Print("M1 SCALPER: STOP PRESSED | New entries DISABLED");
      }

      ObjectSetInteger(0,
                       "M1SCALPER_STOP",
                       OBJPROP_STATE,
                       false);

      UpdateStatus();
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION                                                |
//+------------------------------------------------------------------+
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
            " | Volume=",
            DoubleToString(dealVolume,2),
            " | Price=",
            DoubleToString(dealPrice,_Digits),
            " | Profit=",
            DoubleToString(dealProfit,2));
   }

   UpdateConsecutiveLossesFromDeal(dealTicket);
}

//+------------------------------------------------------------------+
//| CREATE BUTTONS                                                   |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| STATUS DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateStatus()
{
   string tradingState =
      TradingEnabled ? "RUNNING" : "STOPPED";

   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   string protectionText =
      ProfitProtectionActive ? "ACTIVE" : "WAITING";

   Comment(
      "M1 SCALPER v8.0\n",
      "Status: ", tradingState, "\n",
      "Symbol: ", _Symbol, "\n",
      "Timeframe: M1\n",
      "Trend: ", trendText, "\n",
      "Risk/Trade: ",
      DoubleToString(MaximumRiskPercentPerTrade,2),
      "%\n",
      "Profit Protection: ", protectionText, "\n",
      "Peak Profit: $",
      DoubleToString(PeakPositionProfit,2), "\n",
      "Fixed Retrace: $",
      DoubleToString(ProfitRetraceAmount,2), "\n",
      "50% Retrace: ",
      DoubleToString(ProfitRetracePercent,1),
      "%\n",
      "Open Positions: ",
      IntegerToString(CountOpenPositions()), "\n",
      "Exposure Lots: ",
      DoubleToString(GetCurrentExposureLots(),2), "\n",
      "Consecutive Losses: ",
      IntegerToString(ConsecutiveLosses)
   );
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                      |
//+------------------------------------------------------------------+
void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime tm;

   TimeToStruct(TimeCurrent(),
                tm);

   int dayKey =
      tm.year * 10000 +
      tm.mon * 100 +
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
         Print("M1 SCALPER: NEW TRADING DAY | Start Balance=$",
               DoubleToString(DayStartBalance,2));
      }
   }
}

//+------------------------------------------------------------------+
//| PEAK EQUITY                                                      |
//+------------------------------------------------------------------+
void UpdatePeakEquity()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > PeakEquity)
      PeakEquity = equity;
}

//+------------------------------------------------------------------+
//| DAILY LOSS PROTECTION                                            |
//+------------------------------------------------------------------+
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

   return(lossPercent >= DailyLossLimitPercent);
}

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION                                              |
//+------------------------------------------------------------------+
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

   return(drawdownPercent >= MaximumDrawdownPercent);
}

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS PROTECTION                                      |
//+------------------------------------------------------------------+
bool ConsecutiveLossProtection()
{
   if(MaximumConsecutiveLosses <= 0)
      return false;

   return(ConsecutiveLosses >=
          MaximumConsecutiveLosses);
}

//+------------------------------------------------------------------+
//| CAN TRADE                                                        |
//+------------------------------------------------------------------+
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
//| ENOUGH BARS                                                      |
//+------------------------------------------------------------------+
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

   return(bars >= minimumBars);
}

//+------------------------------------------------------------------+
//| CALCULATE LOT                                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| NORMALIZE VOLUME                                                 |
//+------------------------------------------------------------------+
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

   int digits = 2;

   if(step == 1.0)
      digits = 0;
   else if(step == 0.1)
      digits = 1;
   else if(step == 0.01)
      digits = 2;
   else if(step == 0.001)
      digits = 3;

   return NormalizeDouble(volume,
                          digits);
}//+------------------------------------------------------------------+
//| COUNT OPEN POSITIONS                                             |
//+------------------------------------------------------------------+
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

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| CURRENT EXPOSURE                                                 |
//+------------------------------------------------------------------+
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

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      exposure +=
         PositionGetDouble(POSITION_VOLUME);
   }

   return exposure;
}

//+------------------------------------------------------------------+
//| HIGHEST HIGH                                                     |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| LOWEST LOW                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| BULLISH STRUCTURE                                                |
//+------------------------------------------------------------------+
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

   return(recentHigh > previousHigh &&
          recentLow > previousLow);
}

//+------------------------------------------------------------------+
//| BEARISH STRUCTURE                                                |
//+------------------------------------------------------------------+
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

   return(recentHigh < previousHigh &&
          recentLow < previousLow);
}

//+------------------------------------------------------------------+
//| BULLISH MOMENTUM                                                 |
//+------------------------------------------------------------------+
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

   return(currentPrice > openPrice &&
          bodyPercent >= MinimumBodyPercent);
}

//+------------------------------------------------------------------+
//| BEARISH MOMENTUM                                                 |
//+------------------------------------------------------------------+
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

   return(currentPrice < openPrice &&
          bodyPercent >= MinimumBodyPercent);
}

//+------------------------------------------------------------------+
//| BULLISH CONTINUATION BREAKOUT                                   |
//+------------------------------------------------------------------+
bool BullishContinuationBreakout()
{
   double ask =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   if(ask <= 0.0)
      return false;

   double resistance =
      GetHighestHigh(1,
                     ContinuationLookback);

   return(ask > resistance);
}

//+------------------------------------------------------------------+
//| BEARISH CONTINUATION BREAKOUT                                   |
//+------------------------------------------------------------------+
bool BearishContinuationBreakout()
{
   double bid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   double support =
      GetLowestLow(1,
                   ContinuationLookback);

   return(bid < support);
}

//+------------------------------------------------------------------+
//| BULLISH REVERSE BREAKOUT                                        |
//+------------------------------------------------------------------+
bool BullishReverseBreakout()
{
   double ask =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   if(ask <= 0.0)
      return false;

   double level =
      GetHighestHigh(1,
                     ReverseBreakoutLookback);

   return(ask > level);
}

//+------------------------------------------------------------------+
//| BEARISH REVERSE BREAKOUT                                        |
//+------------------------------------------------------------------+
bool BearishReverseBreakout()
{
   double bid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   double level =
      GetLowestLow(1,
                   ReverseBreakoutLookback);

   return(bid < level);
}

//+------------------------------------------------------------------+
//| INITIAL TREND                                                    |
//+------------------------------------------------------------------+
int DetectInitialTrend()
{
   if(IsBullishStructure() &&
      BullishMomentum())
      return TREND_BUY;

   if(IsBearishStructure() &&
      BearishMomentum())
      return TREND_SELL;

   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| UPDATE TREND                                                     |
//+------------------------------------------------------------------+
void UpdateTrendState()
{
   int detected =
      DetectInitialTrend();

   if(detected != TREND_NONE &&
      detected != CurrentTrend)
   {
      CurrentTrend = detected;

      if(EnableExpertLogs)
      {
         if(CurrentTrend == TREND_BUY)
            Print("M1 SCALPER: TREND CHANGED -> BUY");

         if(CurrentTrend == TREND_SELL)
            Print("M1 SCALPER: TREND CHANGED -> SELL");
      }
   }

   if(BullishReverseBreakout())
   {
      if(CurrentTrend != TREND_BUY)
      {
         CurrentTrend = TREND_BUY;

         if(EnableExpertLogs)
            Print("M1 SCALPER: LIVE REVERSAL -> BUY");
      }
   }

   if(BearishReverseBreakout())
   {
      if(CurrentTrend != TREND_SELL)
      {
         CurrentTrend = TREND_SELL;

         if(EnableExpertLogs)
            Print("M1 SCALPER: LIVE REVERSAL -> SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| BUY SCORE                                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| SELL SCORE                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| RISK MONEY                                                       |
//+------------------------------------------------------------------+
double CalculateRiskMoney()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance <= 0.0)
      return 0.0;

   return(balance *
          MaximumRiskPercentPerTrade /
          100.0);
}

//+------------------------------------------------------------------+
//| CALCULATE SAFE STOP LOSS                                        |
//+------------------------------------------------------------------+
bool CalculateSafeStopLoss(
   ENUM_ORDER_TYPE orderType,
   double volume,
   double entryPrice,
   double &stopLoss)
{
   stopLoss = 0.0;

   if(volume <= 0.0 ||
      entryPrice <= 0.0)
      return false;

   double riskMoney =
      CalculateRiskMoney();

   if(riskMoney <= 0.0)
      return false;

   double tickSize =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 ||
      tickValue <= 0.0)
   {
      if(EnableExpertLogs)
         Print("M1 SCALPER: SL CALCULATION FAILED | Invalid tick size/value");

      return false;
   }

   // Maximum price movement allowed for the selected risk.
   double priceDistance =
      riskMoney *
      tickSize /
      (volume * tickValue);

   if(priceDistance <= 0.0)
      return false;

   long stopsLevelPoints =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_STOPS_LEVEL);

   double minimumDistance =
      stopsLevelPoints * _Point;

   // If the broker requires a larger SL distance than our
   // 0.5% risk allows, reject the trade instead of risking more.
   if(minimumDistance > priceDistance)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: ENTRY REJECTED | Broker minimum SL distance would exceed ",
               DoubleToString(MaximumRiskPercentPerTrade,2),
               "% risk");
      }

      return false;
   }

   if(orderType == ORDER_TYPE_BUY)
   {
      stopLoss =
         entryPrice - priceDistance;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      stopLoss =
         entryPrice + priceDistance;
   }
   else
   {
      return false;
   }

   // Normalize to symbol digits.
   stopLoss =
      NormalizeDouble(stopLoss,
                      _Digits);

   // Final safety check.
   if(orderType == ORDER_TYPE_BUY &&
      stopLoss >= entryPrice)
      return false;

   if(orderType == ORDER_TYPE_SELL &&
      stopLoss <= entryPrice)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| CHECK FOR ENTRY                                                  |
//+------------------------------------------------------------------+
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
         Print("M1 SCALPER: ENTRY BLOCKED | Position limit | Open=",
               openPositions,
               " | Maximum=",
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
         Print("M1 SCALPER: ENTRY BLOCKED | Exposure limit | Current=",
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
      Print("M1 SCALPER: SCANNING | BUY=",
            DoubleToString(buyScore,1),
            "% | SELL=",
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

      OpenBuy();
      return;
   }

   if(sellScore >= SignalThreshold &&
      sellScore > buyScore)
   {
      if(EnableExpertLogs)
         Print("M1 SCALPER: SELL CONFIRMED | Score=",
               DoubleToString(sellScore,1),
               "%");

      OpenSell();
      return;
   }

   if(EnableExpertLogs)
      Print("M1 SCALPER: WAITING | No confirmed entry");
}//+------------------------------------------------------------------+
//| OPEN BUY                                                         |
//+------------------------------------------------------------------+
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

   double stopLoss = 0.0;

   if(!CalculateSafeStopLoss(
         ORDER_TYPE_BUY,
         lot,
         ask,
         stopLoss))
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: BUY REJECTED | Could not calculate safe 0.5% SL");
      }

      return false;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   // HARD SL is used.
   // TP remains zero because profit protection manages exits.
   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         stopLoss,
         0.0,
         "M1 Trend BUY");

   if(result)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE OPENED | BUY | Lot=",
               DoubleToString(lot,2),
               " | Entry=",
               DoubleToString(ask,_Digits),
               " | HARD SL=",
               DoubleToString(stopLoss,_Digits),
               " | Max Risk=",
               DoubleToString(MaximumRiskPercentPerTrade,2),
               "%");
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

//+------------------------------------------------------------------+
//| OPEN SELL                                                        |
//+------------------------------------------------------------------+
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

   double stopLoss = 0.0;

   if(!CalculateSafeStopLoss(
         ORDER_TYPE_SELL,
         lot,
         bid,
         stopLoss))
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: SELL REJECTED | Could not calculate safe 0.5% SL");
      }

      return false;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   // HARD SL is used.
   // TP remains zero because profit protection manages exits.
   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         stopLoss,
         0.0,
         "M1 Trend SELL");

   if(result)
   {
      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: TRADE OPENED | SELL | Lot=",
               DoubleToString(lot,2),
               " | Entry=",
               DoubleToString(bid,_Digits),
               " | HARD SL=",
               DoubleToString(stopLoss,_Digits),
               " | Max Risk=",
               DoubleToString(MaximumRiskPercentPerTrade,2),
               "%");
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

//+------------------------------------------------------------------+
//| FIND TRACKED POSITION                                            |
//+------------------------------------------------------------------+
bool FindTrackedPosition(
   ulong &ticket,
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

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
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

//+------------------------------------------------------------------+
//| RESET PROFIT TRACKER                                             |
//+------------------------------------------------------------------+
void ResetProfitTracker()
{
   ProfitProtectionActive = false;
   PeakPositionProfit     = 0.0;
   TrackedPositionTicket  = 0;
}

//+------------------------------------------------------------------+
//| MANAGE PROFIT PROTECTION                                         |
//+------------------------------------------------------------------+
void ManageProfitRetrace()
{
   ulong ticket = 0;
   double profit = 0.0;
   long positionType = -1;

   bool found =
      FindTrackedPosition(
         ticket,
         profit,
         positionType);

   if(!found)
   {
      if(TrackedPositionTicket != 0 ||
         ProfitProtectionActive)
      {
         if(EnableExpertLogs)
            Print("M1 SCALPER: PROFIT TRACKER RESET | No EA position");

         ResetProfitTracker();
      }

      return;
   }

   // New position
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

   // Record highest profit.
   if(profit > PeakPositionProfit)
      PeakPositionProfit = profit;

   // Existing protection activates at $1.
   if(!ProfitProtectionActive &&
      PeakPositionProfit >= ProfitProtectionStart)
   {
      ProfitProtectionActive = true;

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: PROFIT PROTECTION ACTIVE | Peak=$",
               DoubleToString(PeakPositionProfit,2),
               " | Fixed Retrace=$",
               DoubleToString(ProfitRetraceAmount,2),
               " | 50% Retrace");
      }
   }

   if(!ProfitProtectionActive)
      return;

   // EXISTING $0.50 RETRACEMENT RULE
   double fixedProtectionLevel =
      PeakPositionProfit -
      ProfitRetraceAmount;

   bool fixedTriggered =
      (profit <= fixedProtectionLevel);

   // NEW 50% PEAK PROFIT RETRACEMENT RULE
   double percentageProtectionLevel =
      PeakPositionProfit *
      (1.0 - ProfitRetracePercent / 100.0);

   bool percentageTriggered =
      (profit <= percentageProtectionLevel);

   // Either protection can close the trade.
   if(fixedTriggered ||
      percentageTriggered)
   {
      string reason = "";

      if(fixedTriggered &&
         percentageTriggered)
      {
         reason = "BOTH PROTECTIONS";
      }
      else if(fixedTriggered)
      {
         reason = "FIXED $0.50 RETRACE";
      }
      else
      {
         reason = "50% PEAK PROFIT RETRACE";
      }

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: PROFIT PROTECTION TRIGGERED | ",
               reason,
               " | Current=$",
               DoubleToString(profit,2),
               " | Peak=$",
               DoubleToString(PeakPositionProfit,2),
               " | Fixed Level=$",
               DoubleToString(fixedProtectionLevel,2),
               " | 50% Level=$",
               DoubleToString(percentageProtectionLevel,2));
      }

      bool closed =
         trade.PositionClose(ticket);

      if(closed)
      {
         if(EnableExpertLogs)
         {
            Print("M1 SCALPER: PROFIT PROTECTED | Ticket=",
                  ticket,
                  " | Approx Profit=$",
                  DoubleToString(profit,2));
         }

         ResetProfitTracker();
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
      }
   }
}

//+------------------------------------------------------------------+
//| EXPERT STATUS                                                    |
//+------------------------------------------------------------------+
void LogExpertStatus()
{
   if(!EnableExpertLogs)
      return;

   datetime now =
      TimeCurrent();

   if(ExpertLogIntervalSeconds > 0 &&
      (now - LastExpertLogTime) <
      ExpertLogIntervalSeconds)
      return;

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

   string state = "SCANNING";

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
         " | Risk/Trade=",
         DoubleToString(MaximumRiskPercentPerTrade,2),
         "% | Losses=",
         ConsecutiveLosses);
}

//+------------------------------------------------------------------+
//| ENTRY BLOCK REASON                                               |
//+------------------------------------------------------------------+
void LogEntryBlockReason()
{
   if(!EnableExpertLogs)
      return;

   datetime now =
      TimeCurrent();

   if(ExpertLogIntervalSeconds > 0 &&
      (now - LastExpertLogTime) <
      ExpertLogIntervalSeconds)
      return;

   LastExpertLogTime = now;

   if(!TradingEnabled)
   {
      Print("M1 SCALPER: WAITING | Trading STOPPED | Press START");
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

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS TRACKING                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| END OF EA                                                        |
//+------------------------------------------------------------------+
