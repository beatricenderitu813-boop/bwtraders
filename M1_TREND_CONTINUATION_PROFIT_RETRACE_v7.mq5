//+------------------------------------------------------------------+
//| M1_TREND_CONTINUATION_PROFIT_RETRACE_v7.mq5                     |
//| M1 Trend Continuation + Profit Retrace Protection                |
//+------------------------------------------------------------------+
#property strict
#property version   "7.00"
#property description "M1 trend continuation scalper with profit retrace protection"

#include <Trade/Trade.mqh>

CTrade trade;

//-------------------------------------------------------------------
// TREND CONSTANTS
//-------------------------------------------------------------------
#define TREND_NONE  0
#define TREND_BUY   1
#define TREND_SELL -1

//-------------------------------------------------------------------
// GENERAL SETTINGS
//-------------------------------------------------------------------
input bool   StartTradingOnAttach    = false;
input ulong  MagicNumber             = 26092027;

// Signal confirmation
input double SignalThreshold         = 70.0;

// Dynamic lot sizing
// $10   = 0.01
// $100  = 0.10
// $1000 = 1.00
input double LotMultiplier            = 0.001;
input double MaximumLotSize           = 10.0;

// M1 structure
input int    StructureLookback        = 5;
input int    ContinuationLookback     = 5;
input int    ReverseBreakoutLookback  = 5;

input double MinimumBodyPercent       = 50.0;

//-------------------------------------------------------------------
// PROFIT RETRACE SETTINGS
//-------------------------------------------------------------------
// No fixed TP.
// No fixed SL.
//
// Protection starts after this profit is reached.
input double ProfitProtectionStart    = 1.00;

// Once protection is active, close when current profit
// falls this amount below the highest recorded profit.
input double ProfitRetraceAmount      = 0.50;

//-------------------------------------------------------------------
// POSITION LIMITS
//-------------------------------------------------------------------
input int    MaximumOpenPositions     = 1;
input double MaximumEAExposureLots    = 10.0;

//-------------------------------------------------------------------
// ACCOUNT PROTECTION
//-------------------------------------------------------------------
input double DailyLossLimitPercent    = 2.0;
input double MaximumDrawdownPercent   = 5.0;
input int    MaximumConsecutiveLosses = 3;

//-------------------------------------------------------------------
// TRADE SETTINGS
//-------------------------------------------------------------------
input int    SlippagePoints           = 20;

//-------------------------------------------------------------------
// GLOBAL VARIABLES
//-------------------------------------------------------------------
bool   TradingEnabled = false;

int    CurrentTrend = TREND_NONE;

double DayStartBalance = 0.0;
double PeakEquity      = 0.0;

int    ConsecutiveLosses = 0;

int    LastTradingDayKey = 0;

// Profit protection state
bool   ProfitProtectionActive = false;
double PeakPositionProfit     = 0.0;
ulong  TrackedPositionTicket  = 0;

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

bool   EnoughM1Bars();

double CalculateLotSize();
double NormalizeVolume(double volume);

int    CountOpenPositions();
double GetCurrentExposureLots();

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

void   ManageProfitRetrace();

bool   FindTrackedPosition(ulong &ticket,
                           double &profit,
                           long &positionType);

void   ResetProfitTracker();

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

   CurrentTrend = TREND_NONE;

   ProfitProtectionActive = false;
   PeakPositionProfit     = 0.0;
   TrackedPositionTicket  = 0;

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

   // Profit management must continue even when START is off.
   // This means STOP does not leave profit protection disabled.
   ManageProfitRetrace();

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
// CREATE CONTROL BUTTONS
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

   string protectionText =
      ProfitProtectionActive ? "ACTIVE" : "WAITING";

   Comment(
      "M1 TREND CONTINUATION v7\n",
      "Status: ", runText, "\n",
      "Trend: ", trendText, "\n",
      "Profit Protection: ", protectionText, "\n",
      "Peak Profit: $",
      DoubleToString(PeakPositionProfit, 2), "\n",
      "Retrace Amount: $",
      DoubleToString(ProfitRetraceAmount, 2), "\n",
      "Open Positions: ",
      CountOpenPositions(), "\n",
      "Exposure Lots: ",
      DoubleToString(GetCurrentExposureLots(), 2), "\n",
      "Consecutive Losses: ",
      ConsecutiveLosses
   );
}//+------------------------------------------------------------------+
//| DAILY AND ACCOUNT PROTECTION                                     |
//+------------------------------------------------------------------+

void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   int currentDayKey =
      tm.year * 10000 +
      tm.mon * 100 +
      tm.day;

   if(LastTradingDayKey != currentDayKey)
   {
      LastTradingDayKey = currentDayKey;

      DayStartBalance =
         AccountInfoDouble(ACCOUNT_BALANCE);

      PeakEquity =
         AccountInfoDouble(ACCOUNT_EQUITY);

      ConsecutiveLosses = 0;
   }
}

//-------------------------------------------------------------------

void UpdatePeakEquity()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > PeakEquity)
      PeakEquity = equity;
}

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

bool DrawdownProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return false;

   if(PeakEquity <= 0.0)
      return false;

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   double drawdownPercent =
      ((PeakEquity - equity) /
       PeakEquity) * 100.0;

   if(drawdownPercent >= MaximumDrawdownPercent)
      return true;

   return false;
}

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

   int bars =
      Bars(_Symbol, PERIOD_M1);

   if(bars < requiredBars)
      return false;

   return true;
}

//-------------------------------------------------------------------

double GetHighestHigh(int startShift, int count)
{
   double highest = -DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double high =
         iHigh(_Symbol, PERIOD_M1, i);

      if(high > highest)
         highest = high;
   }

   return highest;
}

//-------------------------------------------------------------------

double GetLowestLow(int startShift, int count)
{
   double lowest = DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double low =
         iLow(_Symbol, PERIOD_M1, i);

      if(low < lowest)
         lowest = low;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| M1 STRUCTURE                                                     |
//+------------------------------------------------------------------+

bool IsBullishStructure()
{
   double high1 =
      iHigh(_Symbol, PERIOD_M1, 1);

   double high2 =
      iHigh(_Symbol, PERIOD_M1, 2);

   double low1 =
      iLow(_Symbol, PERIOD_M1, 1);

   double low2 =
      iLow(_Symbol, PERIOD_M1, 2);

   if(high1 > high2 &&
      low1 > low2)
      return true;

   return false;
}

//-------------------------------------------------------------------

bool IsBearishStructure()
{
   double high1 =
      iHigh(_Symbol, PERIOD_M1, 1);

   double high2 =
      iHigh(_Symbol, PERIOD_M1, 2);

   double low1 =
      iLow(_Symbol, PERIOD_M1, 1);

   double low2 =
      iLow(_Symbol, PERIOD_M1, 2);

   if(high1 < high2 &&
      low1 < low2)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CURRENT M1 MOMENTUM                                              |
//+------------------------------------------------------------------+

bool BullishMomentum()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double openPrice =
      iOpen(_Symbol, PERIOD_M1, 0);

   double highPrice =
      iHigh(_Symbol, PERIOD_M1, 0);

   double lowPrice =
      iLow(_Symbol, PERIOD_M1, 0);

   double range =
      highPrice - lowPrice;

   if(range <= 0.0)
      return false;

   double body =
      MathAbs(tick.bid - openPrice);

   double bodyPercent =
      (body / range) * 100.0;

   if(tick.bid > openPrice &&
      bodyPercent >= MinimumBodyPercent)
      return true;

   return false;
}

//-------------------------------------------------------------------

bool BearishMomentum()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double openPrice =
      iOpen(_Symbol, PERIOD_M1, 0);

   double highPrice =
      iHigh(_Symbol, PERIOD_M1, 0);

   double lowPrice =
      iLow(_Symbol, PERIOD_M1, 0);

   double range =
      highPrice - lowPrice;

   if(range <= 0.0)
      return false;

   double body =
      MathAbs(tick.bid - openPrice);

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

void UpdateTrendState()
{
   if(CurrentTrend == TREND_NONE)
   {
      CurrentTrend =
         DetectInitialTrend();

      return;
   }

   if(CurrentTrend == TREND_BUY)
   {
      if(BullishReverseBreakout())
         CurrentTrend = TREND_SELL;

      return;
   }

   if(CurrentTrend == TREND_SELL)
   {
      if(BearishReverseBreakout())
         CurrentTrend = TREND_BUY;

      return;
   }
}

//+------------------------------------------------------------------+
//| SCORING                                                          |
//+------------------------------------------------------------------+

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
}//+------------------------------------------------------------------+
//| LOT MANAGEMENT                                                   |
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

double CalculateLotSize()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double lot =
      balance * LotMultiplier;

   return NormalizeVolume(lot);
}

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

double GetCurrentExposureLots()
{
   double totalLots = 0.0;

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
//| ENTRY                                                            |
//+------------------------------------------------------------------+

void CheckForEntry()
{
   if(!CanTrade())
      return;

   if(CountOpenPositions() >=
      MaximumOpenPositions)
      return;

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
      return;

   if(MaximumEAExposureLots > 0.0)
   {
      double exposure =
         GetCurrentExposureLots();

      if(exposure + lot >
         MaximumEAExposureLots)
         return;
   }

   if(CurrentTrend == TREND_BUY)
   {
      double buyScore =
         GetBuyScore();

      if(buyScore >= SignalThreshold)
         OpenBuy();

      return;
   }

   if(CurrentTrend == TREND_SELL)
   {
      double sellScore =
         GetSellScore();

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

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
      return false;

   // NO SL
   // NO TP
   //
   // The trade is managed by the profit-retrace system.
   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         0.0,
         0.0,
         "M1 Trend BUY"
      );

   if(result)
   {
      ResetProfitTracker();
   }

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

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
      return false;

   // NO SL
   // NO TP
   //
   // The trade is managed by the profit-retrace system.
   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         0.0,
         0.0,
         "M1 Trend SELL"
      );

   if(result)
   {
      ResetProfitTracker();
   }

   return result;
}

//+------------------------------------------------------------------+
//| FIND CURRENT EA POSITION                                         |
//+------------------------------------------------------------------+

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
      ulong currentTicket =
         PositionGetTicket(i);

      if(currentTicket == 0)
         continue;

      if(!PositionSelectByTicket(currentTicket))
         continue;

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      if(magic != (long)MagicNumber)
         continue;

      if(symbol != _Symbol)
         continue;

      ticket = currentTicket;

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
//| PROFIT RETRACE MANAGEMENT                                        |
//+------------------------------------------------------------------+

void ManageProfitRetrace()
{
   ulong ticket = 0;
   double currentProfit = 0.0;
   long positionType = -1;

   bool found =
      FindTrackedPosition(
         ticket,
         currentProfit,
         positionType
      );

   // No position exists.
   if(!found)
   {
      if(TrackedPositionTicket != 0)
         ResetProfitTracker();

      return;
   }

   // New position.
   if(TrackedPositionTicket != ticket)
   {
      TrackedPositionTicket = ticket;

      ProfitProtectionActive = false;
      PeakPositionProfit = currentProfit;
   }

   // Record the highest profit reached.
   if(currentProfit > PeakPositionProfit)
      PeakPositionProfit = currentProfit;

   // Protection has not started yet.
   if(!ProfitProtectionActive)
   {
      if(currentProfit >= ProfitProtectionStart)
      {
         ProfitProtectionActive = true;

         PeakPositionProfit =
            currentProfit;
      }

      return;
   }

   // Update peak while protection is active.
   if(currentProfit > PeakPositionProfit)
      PeakPositionProfit = currentProfit;

   // Calculate the permitted retracement.
   double protectedProfit =
      PeakPositionProfit -
      ProfitRetraceAmount;

   // Close only when the trade has retraced
   // by the chosen amount from its peak.
   if(currentProfit <= protectedProfit)
   {
      bool closed =
         trade.PositionClose(ticket);

      if(closed)
      {
         ResetProfitTracker();
      }
   }
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

   // Only closing deals.
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
