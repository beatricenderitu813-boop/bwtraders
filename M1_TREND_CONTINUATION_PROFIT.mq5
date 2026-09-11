//+------------------------------------------------------------------+
//| M1_TREND_CONTINUATION_PROFIT_RETRACE_v7_1_CLEAN.mq5             |
//| M1 Trend Continuation Scalper - Expert Logs                     |
//+------------------------------------------------------------------+
#property strict
#property version   "7.10"
#property description "M1 Trend Continuation Scalper with profit retrace protection and Expert logs."

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

input bool   StartTradingOnAttach      = false;
input ulong  MagicNumber               = 26092027;

input double SignalThreshold           = 70.0;
input double LotMultiplier              = 0.001;
input double MaximumLotSize            = 10.0;

input int    StructureLookback         = 5;
input int    ContinuationLookback      = 5;
input int    ReverseBreakoutLookback   = 5;

input double MinimumBodyPercent         = 50.0;

input double ProfitProtectionStart     = 1.00;
input double ProfitRetraceAmount       = 0.50;

input int    MaximumOpenPositions      = 1;
input double MaximumEAExposureLots     = 10.0;

input double DailyLossLimitPercent     = 2.0;
input double MaximumDrawdownPercent    = 5.0;
input int    MaximumConsecutiveLosses  = 3;

input int    SlippagePoints             = 20;

input bool   EnableExpertLogs           = true;
input int    ExpertLogIntervalSeconds  = 3;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+

bool TradingEnabled = false;

datetime LastExpertLogTime = 0;
string   LastExpertState   = "";

double StartingEquity = 0.0;
double PeakEquity     = 0.0;

int ConsecutiveLosses = 0;

bool ProfitProtectionActive = false;
double PeakPositionProfit   = 0.0;
ulong TrackedPositionTicket = 0;

enum TrendDirection
{
   TREND_NONE = 0,
   TREND_BUY  = 1,
   TREND_SELL = -1
};

TrendDirection CurrentTrend = TREND_NONE;

//+------------------------------------------------------------------+
//| FUNCTION DECLARATIONS                                            |
//+------------------------------------------------------------------+

void CreateControlButtons();
void DeleteControlButtons();

void UpdateStatus();
void UpdateTrendState();

void CheckForEntry();
void LogEntryBlockReason();
void LogExpertStatus();

bool EnoughM1Bars();

double GetHighestHigh(int startShift,int count);
double GetLowestLow(int startShift,int count);

bool IsBullishStructure();
bool IsBearishStructure();

bool BullishMomentum();
bool BearishMomentum();

bool BullishContinuationBreakout();
bool BearishContinuationBreakout();

bool BullishReverseBreakout();
bool BearishReverseBreakout();

int DetectInitialTrend();

double GetBuyScore();
double GetSellScore();

double NormalizeVolume(double volume);
double CalculateLotSize();

int CountOpenPositions();
double GetCurrentExposureLots();

bool OpenBuy();
bool OpenSell();

bool FindTrackedPosition(
   ulong &ticket,
   double &profit,
   long &positionType
);

void ResetProfitTracker();
void ManageProfitRetrace();

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket
);

bool DailyLossProtection();
bool DrawdownProtection();
bool ConsecutiveLossProtection();
bool CanTrade();

double GetDailyClosedProfit();

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   StartingEquity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   PeakEquity = StartingEquity;

   TradingEnabled = StartTradingOnAttach;

   CreateControlButtons();
   UpdateStatus();

   if(EnableExpertLogs)
   {
      Print("M1 SCALPER: EA INITIALIZED | Symbol=",
            _Symbol,
            " | M1 | Trading=",
            TradingEnabled ? "RUNNING" : "STOPPED",
            " | Threshold=",
            DoubleToString(SignalThreshold,1),
            "%");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   DeleteControlButtons();

   if(EnableExpertLogs)
   {
      Print("M1 SCALPER: EA DEINITIALIZED | Reason=",
            reason);
   }
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+

void OnTick()
{
   PeakEquity =
      MathMax(
         PeakEquity,
         AccountInfoDouble(ACCOUNT_EQUITY)
      );

   UpdateTrendState();

   UpdateStatus();

   LogExpertStatus();

   ManageProfitRetrace();

   if(!EnoughM1Bars())
      return;

   if(!TradingEnabled)
      return;

   CheckForEntry();
}

//+------------------------------------------------------------------+
//| CHART EVENTS                                                      |
//+------------------------------------------------------------------+

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "M1_START_BUTTON")
   {
      TradingEnabled = true;

      UpdateStatus();

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: START PRESSED | Trading is now RUNNING | Symbol=",
               _Symbol);
      }
   }

   if(sparam == "M1_STOP_BUTTON")
   {
      TradingEnabled = false;

      UpdateStatus();

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: STOP PRESSED | New entries are now STOPPED");
      }
   }

   if(sparam == "M1_EMERGENCY_BUTTON")
   {
      TradingEnabled = false;

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
            trade.PositionClose(ticket);
         }
      }

      ResetProfitTracker();

      UpdateStatus();

      if(EnableExpertLogs)
      {
         Print("M1 SCALPER: EMERGENCY STOP | EA positions closed");
      }
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION                                                |
//+------------------------------------------------------------------+

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   if(trans.deal == 0)
      return;

   UpdateConsecutiveLossesFromDeal(trans.deal);

   if(EnableExpertLogs)
   {
      if(HistoryDealSelect(trans.deal))
      {
         double profit =
            HistoryDealGetDouble(
               trans.deal,
               DEAL_PROFIT
            );

         long entryType =
            HistoryDealGetInteger(
               trans.deal,
               DEAL_ENTRY
            );

         Print("M1 SCALPER: DEAL EVENT | Deal=",
               trans.deal,
               " | EntryType=",
               entryType,
               " | Profit=$",
               DoubleToString(profit,2),
               " | ConsecutiveLosses=",
               ConsecutiveLosses);
      }
   }
}

//+------------------------------------------------------------------+
//| BUTTONS                                                          |
//+------------------------------------------------------------------+

void CreateControlButtons()
{
   ObjectDelete(0,"M1_START_BUTTON");
   ObjectDelete(0,"M1_STOP_BUTTON");
   ObjectDelete(0,"M1_EMERGENCY_BUTTON");

   ObjectCreate(
      0,
      "M1_START_BUTTON",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "M1_START_BUTTON",
      OBJPROP_CORNER,
      CORNER_RIGHT_UPPER
   );

   ObjectSetInteger(
      0,
      "M1_START_BUTTON",
      OBJPROP_XDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M1_START_BUTTON",
      OBJPROP_YDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M1_START_BUTTON",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "M1_START_BUTTON",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "M1_START_BUTTON",
      OBJPROP_TEXT,
      "START"
   );

   ObjectCreate(
      0,
      "M1_STOP_BUTTON",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_CORNER,
      CORNER_RIGHT_UPPER
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_XDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_YDISTANCE,
      55
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_TEXT,
      "STOP"
   );

   ObjectCreate(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_CORNER,
      CORNER_RIGHT_UPPER
   );

   ObjectSetInteger(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_XDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_YDISTANCE,
      90
   );

   ObjectSetInteger(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "M1_EMERGENCY_BUTTON",
      OBJPROP_TEXT,
      "EMERGENCY"
   );
}

//+------------------------------------------------------------------+

void DeleteControlButtons()
{
   ObjectDelete(0,"M1_START_BUTTON");
   ObjectDelete(0,"M1_STOP_BUTTON");
   ObjectDelete(0,"M1_EMERGENCY_BUTTON");
}

//+------------------------------------------------------------------+
//| STATUS                                                           |
//+------------------------------------------------------------------+

void UpdateStatus()
{
   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   else
   if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   string status =
      TradingEnabled ? "RUNNING" : "WAITING";

   Comment(
      "M1 TREND CONTINUATION SCALPER\n",
      "Symbol: ",_Symbol,"\n",
      "Timeframe: M1\n",
      "Status: ",status,"\n",
      "Trend: ",trendText,"\n",
      "Buy Score: ",
      DoubleToString(GetBuyScore(),1),"%\n",
      "Sell Score: ",
      DoubleToString(GetSellScore(),1),"%\n",
      "Open Positions: ",
      CountOpenPositions(),"/",
      MaximumOpenPositions,"\n",
      "Consecutive Losses: ",
      ConsecutiveLosses
   );
}

//+------------------------------------------------------------------+
//| DAILY LOSS PROTECTION                                            |
//+------------------------------------------------------------------+

double GetDailyClosedProfit()
{
   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now,dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime dayStart =
      StructToTime(dt);

   if(!HistorySelect(dayStart,now))
      return 0.0;

   double total = 0.0;

   int deals =
      HistoryDealsTotal();

   for(int i = 0;
       i < deals;
       i++)
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);

      if(dealTicket == 0)
         continue;

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

      long entry =
         HistoryDealGetInteger(
            dealTicket,
            DEAL_ENTRY
         );

      if(symbol != _Symbol)
         continue;

      if(magic != (long)MagicNumber)
         continue;

      if(entry != DEAL_ENTRY_OUT &&
         entry != DEAL_ENTRY_OUT_BY)
         continue;

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_PROFIT
         );

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_SWAP
         );

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_COMMISSION
         );
   }

   return total;
}

//+------------------------------------------------------------------+

bool DailyLossProtection()
{
   if(DailyLossLimitPercent <= 0.0)
      return false;

   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance <= 0.0)
      return false;

   double dailyProfit =
      GetDailyClosedProfit();

   double lossLimit =
      balance *
      DailyLossLimitPercent /
      100.0;

   if(dailyProfit <= -lossLimit)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| DRAWDOWN PROTECTION                                              |
//+------------------------------------------------------------------+

bool DrawdownProtection()
{
   if(MaximumDrawdownPercent <= 0.0)
      return false;

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(PeakEquity <= 0.0)
      return false;

   double drawdown =
      ((PeakEquity - equity) /
       PeakEquity) * 100.0;

   if(drawdown >= MaximumDrawdownPercent)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS PROTECTION                                      |
//+------------------------------------------------------------------+

bool ConsecutiveLossProtection()
{
   if(MaximumConsecutiveLosses <= 0)
      return false;

   if(ConsecutiveLosses >=
      MaximumConsecutiveLosses)
      return true;

   return false;
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
      Bars(_Symbol,PERIOD_M1);

   if(bars < requiredBars)
      return false;

   return true;
}

//+------------------------------------------------------------------+

double GetHighestHigh(
   int startShift,
   int count
)
{
   double highest = -DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double high =
         iHigh(
            _Symbol,
            PERIOD_M1,
            i
         );

      if(high > highest)
         highest = high;
   }

   return highest;
}

//+------------------------------------------------------------------+

double GetLowestLow(
   int startShift,
   int count
)
{
   double lowest = DBL_MAX;

   for(int i = startShift;
       i < startShift + count;
       i++)
   {
      double low =
         iLow(
            _Symbol,
            PERIOD_M1,
            i
         );

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
      iHigh(_Symbol,PERIOD_M1,1);

   double high2 =
      iHigh(_Symbol,PERIOD_M1,2);

   double low1 =
      iLow(_Symbol,PERIOD_M1,1);

   double low2 =
      iLow(_Symbol,PERIOD_M1,2);

   if(high1 > high2 &&
      low1 > low2)
      return true;

   return false;
}

//+------------------------------------------------------------------+

bool IsBearishStructure()
{
   double high1 =
      iHigh(_Symbol,PERIOD_M1,1);

   double high2 =
      iHigh(_Symbol,PERIOD_M1,2);

   double low1 =
      iLow(_Symbol,PERIOD_M1,1);

   double low2 =
      iLow(_Symbol,PERIOD_M1,2);

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

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double openPrice =
      iOpen(_Symbol,PERIOD_M1,0);

   double highPrice =
      iHigh(_Symbol,PERIOD_M1,0);

   double lowPrice =
      iLow(_Symbol,PERIOD_M1,0);

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

//+------------------------------------------------------------------+

bool BearishMomentum()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double openPrice =
      iOpen(_Symbol,PERIOD_M1,0);

   double highPrice =
      iHigh(_Symbol,PERIOD_M1,0);

   double lowPrice =
      iLow(_Symbol,PERIOD_M1,0);

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

//+------------------------------------------------------------------+//+------------------------------------------------------------------+
//| CONTINUATION BREAKOUT                                            |
//+------------------------------------------------------------------+

bool BullishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double previousHigh =
      GetHighestHigh(
         1,
         ContinuationLookback
      );

   if(tick.ask > previousHigh)
      return true;

   return false;
}

//+------------------------------------------------------------------+

bool BearishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double previousLow =
      GetLowestLow(
         1,
         ContinuationLookback
      );

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

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double previousLow =
      GetLowestLow(
         1,
         ReverseBreakoutLookback
      );

   if(tick.bid < previousLow)
   {
      if(BearishMomentum())
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+

bool BearishReverseBreakout()
{
   if(CurrentTrend != TREND_SELL)
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double previousHigh =
      GetHighestHigh(
         1,
         ReverseBreakoutLookback
      );

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
   {
      return TREND_BUY;
   }

   if(bearishStructure &&
      bearishMomentum)
   {
      return TREND_SELL;
   }

   return TREND_NONE;
}

//+------------------------------------------------------------------+

void UpdateTrendState()
{
   if(CurrentTrend == TREND_NONE)
   {
      CurrentTrend =
         (TrendDirection)DetectInitialTrend();

      return;
   }

   if(CurrentTrend == TREND_BUY)
   {
      if(BullishReverseBreakout())
      {
         CurrentTrend = TREND_SELL;
      }

      return;
   }

   if(CurrentTrend == TREND_SELL)
   {
      if(BearishReverseBreakout())
      {
         CurrentTrend = TREND_BUY;
      }

      return;
   }
}

//+------------------------------------------------------------------+
//| BUY SCORE                                                        |
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

   if(!SymbolInfoTick(_Symbol,tick))
      return score;

   double currentOpen =
      iOpen(
         _Symbol,
         PERIOD_M1,
         0
      );

   if(tick.bid > currentOpen)
      score += 20.0;

   if(BullishContinuationBreakout())
      score += 25.0;

   return score;
}

//+------------------------------------------------------------------+
//| SELL SCORE                                                       |
//+------------------------------------------------------------------+

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

   if(!SymbolInfoTick(_Symbol,tick))
      return score;

   double currentOpen =
      iOpen(
         _Symbol,
         PERIOD_M1,
         0
      );

   if(tick.bid < currentOpen)
      score += 20.0;

   if(BearishContinuationBreakout())
      score += 25.0;

   return score;
}

//+------------------------------------------------------------------+
//| LOT MANAGEMENT                                                   |
//+------------------------------------------------------------------+

double NormalizeVolume(double volume)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

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

   return NormalizeDouble(
      volume,
      digits
   );
}

//+------------------------------------------------------------------+

double CalculateLotSize()
{
   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );

   double lot =
      balance * LotMultiplier;

   return NormalizeVolume(lot);
}

//+------------------------------------------------------------------+
//| COUNT EA POSITIONS                                               |
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

      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      if(magic == (long)MagicNumber &&
         symbol == _Symbol)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| CURRENT EXPOSURE                                                 |
//+------------------------------------------------------------------+

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
         PositionGetInteger(
            POSITION_MAGIC
         );

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      if(magic == (long)MagicNumber &&
         symbol == _Symbol)
      {
         totalLots +=
            PositionGetDouble(
               POSITION_VOLUME
            );
      }
   }

   return totalLots;
}

//+------------------------------------------------------------------+
//| ENTRY LOGIC                                                      |
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
      LogEntryBlockReason();
      return;
   }

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: WAITING | Invalid lot size"
         );
      }

      return;
   }

   double currentExposure =
      GetCurrentExposureLots();

   if(MaximumEAExposureLots > 0.0 &&
      currentExposure + lot >
      MaximumEAExposureLots)
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: WAITING | Exposure limit | Current=",
            DoubleToString(currentExposure,2),
            " | New=",
            DoubleToString(lot,2),
            " | Maximum=",
            DoubleToString(
               MaximumEAExposureLots,
               2
            )
         );
      }

      return;
   }

   // BUY SCAN
   if(CurrentTrend == TREND_BUY)
   {
      double buyScore =
         GetBuyScore();

      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: SCANNING BUY | Score=",
            DoubleToString(buyScore,1),
            "% | Required=",
            DoubleToString(
               SignalThreshold,
               1
            ),
            "%"
         );
      }

      if(buyScore >= SignalThreshold)
      {
         if(EnableExpertLogs)
         {
            Print(
               "M1 SCALPER: BUY CONFIRMED | Score=",
               DoubleToString(buyScore,1),
               "% | Opening trade..."
            );
         }

         OpenBuy();
      }

      return;
   }

   // SELL SCAN
   if(CurrentTrend == TREND_SELL)
   {
      double sellScore =
         GetSellScore();

      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: SCANNING SELL | Score=",
            DoubleToString(sellScore,1),
            "% | Required=",
            DoubleToString(
               SignalThreshold,
               1
            ),
            "%"
         );
      }

      if(sellScore >= SignalThreshold)
      {
         if(EnableExpertLogs)
         {
            Print(
               "M1 SCALPER: SELL CONFIRMED | Score=",
               DoubleToString(sellScore,1),
               "% | Opening trade..."
            );
         }

         OpenSell();
      }

      return;
   }

   if(EnableExpertLogs)
   {
      Print(
         "M1 SCALPER: WAITING | No BUY/SELL trend confirmation yet"
      );
   }
}

//+------------------------------------------------------------------+
//| ENTRY BLOCK REASON                                               |
//+------------------------------------------------------------------+

void LogEntryBlockReason()
{
   if(!EnableExpertLogs)
      return;

   if(!TradingEnabled)
   {
      Print(
         "M1 SCALPER: WAITING | Trading STOPPED - press START"
      );

      return;
   }

   if(DailyLossProtection())
   {
      Print(
         "M1 SCALPER: WAITING | Daily loss protection active"
      );

      return;
   }

   if(DrawdownProtection())
   {
      Print(
         "M1 SCALPER: WAITING | Drawdown protection active"
      );

      return;
   }

   if(ConsecutiveLossProtection())
   {
      Print(
         "M1 SCALPER: WAITING | Consecutive-loss protection active | Losses=",
         ConsecutiveLosses
      );

      return;
   }

   if(CountOpenPositions() >=
      MaximumOpenPositions)
   {
      Print(
         "M1 SCALPER: WAITING | Maximum open positions reached | Open=",
         CountOpenPositions(),
         " / ",
         MaximumOpenPositions
      );

      return;
   }

   Print(
      "M1 SCALPER: WAITING | Entry conditions not currently permitted"
   );
}

//+------------------------------------------------------------------+//+------------------------------------------------------------------+
//| EXPERT STATUS LOG                                                |
//+------------------------------------------------------------------+

void LogExpertStatus()
{
   if(!EnableExpertLogs)
      return;

   datetime now = TimeCurrent();

   if(LastExpertLogTime != 0 &&
      now - LastExpertLogTime <
      ExpertLogIntervalSeconds)
   {
      return;
   }

   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY";

   else if(CurrentTrend == TREND_SELL)
      trendText = "SELL";

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   if(!TradingEnabled)
   {
      Print(
         "M1 SCALPER: WAITING | Trading STOPPED | Trend=",
         trendText,
         " | BuyScore=",
         DoubleToString(buyScore,1),
         "% | SellScore=",
         DoubleToString(sellScore,1),
         "%"
      );
   }
   else
   {
      Print(
         "M1 SCALPER: SCANNING | Symbol=",
         _Symbol,
         " | M1 | Trend=",
         trendText,
         " | BuyScore=",
         DoubleToString(buyScore,1),
         "% | SellScore=",
         DoubleToString(sellScore,1),
         "% | Open=",
         CountOpenPositions()
      );
   }

   LastExpertLogTime = now;
}

//+------------------------------------------------------------------+
//| OPEN BUY                                                         |
//+------------------------------------------------------------------+

bool OpenBuy()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: BUY FAILED | Unable to read market price"
         );
      }

      return false;
   }

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: BUY FAILED | Invalid lot size"
         );
      }

      return false;
   }

   // No fixed SL.
   // No fixed TP.
   // Profit is protected by the retracement system.

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
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: BUY OPENED | Lot=",
            DoubleToString(lot,2),
            " | Price=",
            DoubleToString(tick.ask,_Digits),
            " | Order=",
            trade.ResultOrder(),
            " | Retcode=",
            trade.ResultRetcode()
         );
      }

      ResetProfitTracker();
      return true;
   }

   if(EnableExpertLogs)
   {
      Print(
         "M1 SCALPER: BUY FAILED | Retcode=",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );
   }

   return false;
}

//+------------------------------------------------------------------+
//| OPEN SELL                                                        |
//+------------------------------------------------------------------+

bool OpenSell()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: SELL FAILED | Unable to read market price"
         );
      }

      return false;
   }

   double lot =
      CalculateLotSize();

   if(lot <= 0.0)
   {
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: SELL FAILED | Invalid lot size"
         );
      }

      return false;
   }

   // No fixed SL.
   // No fixed TP.
   // Profit is protected by the retracement system.

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
      if(EnableExpertLogs)
      {
         Print(
            "M1 SCALPER: SELL OPENED | Lot=",
            DoubleToString(lot,2),
            " | Price=",
            DoubleToString(tick.bid,_Digits),
            " | Order=",
            trade.ResultOrder(),
            " | Retcode=",
            trade.ResultRetcode()
         );
      }

      ResetProfitTracker();
      return true;
   }

   if(EnableExpertLogs)
   {
      Print(
         "M1 SCALPER: SELL FAILED | Retcode=",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );
   }

   return false;
}

//+------------------------------------------------------------------+
//| FIND TRACKED POSITION                                            |
//+------------------------------------------------------------------+

bool FindTrackedPosition(
   ulong &ticket,
   double &profit,
   long &positionType
)
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
         PositionGetInteger(
            POSITION_MAGIC
         );

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      if(magic != (long)MagicNumber)
         continue;

      if(symbol != _Symbol)
         continue;

      ticket = currentTicket;

      profit =
         PositionGetDouble(
            POSITION_PROFIT
         );

      positionType =
         PositionGetInteger(
            POSITION_TYPE
         );

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
   PeakPositionProfit = 0.0;
   TrackedPositionTicket = 0;
}

//+------------------------------------------------------------------+
//| PROFIT RETRACE                                                   |
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

   // Update highest profit.
   if(currentProfit > PeakPositionProfit)
      PeakPositionProfit = currentProfit;

   // Activate protection once profit reaches the start level.
   if(!ProfitProtectionActive)
   {
      if(currentProfit >= ProfitProtectionStart)
      {
         ProfitProtectionActive = true;

         PeakPositionProfit =
            currentProfit;

         if(EnableExpertLogs)
         {
            Print(
               "M1 SCALPER: PROFIT PROTECTION ACTIVE | Current=$",
               DoubleToString(currentProfit,2),
               " | Peak=$",
               DoubleToString(PeakPositionProfit,2),
               " | Retrace=$",
               DoubleToString(ProfitRetraceAmount,2)
            );
         }
      }

      return;
   }

   // Keep tracking the highest profit.
   if(currentProfit > PeakPositionProfit)
      PeakPositionProfit = currentProfit;

   double protectedProfit =
      PeakPositionProfit -
      ProfitRetraceAmount;

   // Close only after profit retraces by the selected amount.
   //
   // IMPORTANT:
   // This does not intentionally close a position simply because
   // it is losing. Protection begins only after profit is reached.

   if(currentProfit <= protectedProfit &&
      PeakPositionProfit >= ProfitProtectionStart)
   {
      bool closed =
         trade.PositionClose(ticket);

      if(closed)
      {
         if(EnableExpertLogs)
         {
            Print(
               "M1 SCALPER: POSITION CLOSED BY PROFIT RETRACE | Current=$",
               DoubleToString(currentProfit,2),
               " | Peak=$",
               DoubleToString(PeakPositionProfit,2),
               " | Retrace=$",
               DoubleToString(ProfitRetraceAmount,2)
            );
         }

         ResetProfitTracker();
      }
      else
      {
         if(EnableExpertLogs)
         {
            Print(
               "M1 SCALPER: PROFIT RETRACE CLOSE FAILED | Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS TRACKING                                        |
//+------------------------------------------------------------------+

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket
)
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

   if(entryType != DEAL_ENTRY_OUT &&
      entryType != DEAL_ENTRY_OUT_BY)
   {
      return;
   }

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
//| END OF EA                                                        |
//+------------------------------------------------------------------+
