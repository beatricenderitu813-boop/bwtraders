//+------------------------------------------------------------------+
//| M1_TREND_CONTINUATION_SCALPER_AI_v5.mq5                          |
//| M1 ONLY - Trend Continuation + Reverse Breakout                  |
//+------------------------------------------------------------------+
#property strict
#property version   "5.00"
#property description "M1 trend continuation scalper"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input bool   StartTradingOnAttach     = false;
input ulong  MagicNumber              = 26092026;

// Confirmation
input double SignalThreshold          = 70.0;

// Dynamic lot
input double LotMultiplier             = 0.001;
input double MaximumLotSize            = 10.0;

// Structure
input int    StructureLookback         = 5;
input int    ReverseBreakoutLookback   = 5;

// Momentum
input double MinimumBodyPercent        = 55.0;

// Stop-loss
input int    SLBufferPoints             = 50;

// Take profit
input double RiskRewardRatio            = 2.0;

// Position control
input int    MaximumOpenPositions       = 1;
input double MaximumEAExposureLots      = 10.0;

// Protection
input double DailyLossLimitPercent      = 2.0;
input double MaximumDrawdownPercent     = 5.0;
input int    MaximumConsecutiveLosses   = 3;

// Execution
input ulong  SlippagePoints             = 20;

//==================================================================
// TREND CONSTANTS
//==================================================================

#define TREND_NONE  0
#define TREND_BUY   1
#define TREND_SELL -1

//==================================================================
// GLOBAL VARIABLES
//==================================================================

bool TradingEnabled = false;

int CurrentTrend = TREND_NONE;

double DayStartBalance = 0.0;
double PeakEquity      = 0.0;

int ConsecutiveLosses = 0;
int LastTradingDayKey = -1;

//==================================================================
// FUNCTION DECLARATIONS
//==================================================================

void CreateControlButtons();
void DeleteControlButtons();
void UpdateStatus();

void UpdateDailyStatistics();
void ResetDailyStatisticsIfNeeded();

bool DailyLossProtection();
bool DrawdownProtection();
bool ConsecutiveLossProtection();
bool CanTrade();

double NormalizeLot(double lots);
double CalculateDynamicLot();

int CountEAOpenPositions();
double GetEAExposureLots();

double GetHighestHigh(
   ENUM_TIMEFRAMES timeframe,
   int startShift,
   int count
);

double GetLowestLow(
   ENUM_TIMEFRAMES timeframe,
   int startShift,
   int count
);

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

bool OpenBuy();
bool OpenSell();

void CheckForEntry();

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket
);

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   DayStartBalance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   PeakEquity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   LastTradingDayKey =
      now.year * 10000 +
      now.mon * 100 +
      now.day;

   ConsecutiveLosses = 0;

   CurrentTrend = TREND_NONE;

   TradingEnabled = StartTradingOnAttach;

   CreateControlButtons();

   Print("==========================================");
   Print("M1 TREND CONTINUATION SCALPER AI v5");
   Print("TIMEFRAME: M1 ONLY");
   Print("Trend continuation: ENABLED");
   Print("Reverse breakout switching: ENABLED");
   Print("Structure-based SL: ENABLED");
   Print("Risk/Reward TP: ENABLED");
   Print("==========================================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================

void OnDeinit(const int reason)
{
   DeleteControlButtons();
   Comment("");
}

//==================================================================
// MAIN TICK
//==================================================================

void OnTick()
{
   UpdateDailyStatistics();

   ResetDailyStatisticsIfNeeded();

   UpdateTrendState();

   UpdateStatus();

   if(!TradingEnabled)
      return;

   CheckForEntry();
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

   if(trans.deal == 0)
      return;

   UpdateConsecutiveLossesFromDeal(trans.deal);
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

   if(sparam == "M1_START_BUTTON")
   {
      TradingEnabled = true;

      Print("M1 TREND SCALPER STARTED.");
   }

   if(sparam == "M1_STOP_BUTTON")
   {
      TradingEnabled = false;

      Print("M1 TREND SCALPER STOPPED.");
      Print("Existing position will remain open.");
   }

   UpdateStatus();
}

//==================================================================
// CREATE BUTTONS
//==================================================================

void CreateControlButtons()
{
   ObjectDelete(0, "M1_START_BUTTON");
   ObjectDelete(0, "M1_STOP_BUTTON");

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
      OBJPROP_XDISTANCE,
      130
   );

   ObjectSetInteger(
      0,
      "M1_STOP_BUTTON",
      OBJPROP_YDISTANCE,
      20
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

   ChartRedraw();
}

//==================================================================
// DELETE BUTTONS
//==================================================================

void DeleteControlButtons()
{
   ObjectDelete(0, "M1_START_BUTTON");
   ObjectDelete(0, "M1_STOP_BUTTON");
}

//==================================================================
// STATUS
//==================================================================

void UpdateStatus()
{
   string trendText = "NONE";

   if(CurrentTrend == TREND_BUY)
      trendText = "BUY TREND";

   if(CurrentTrend == TREND_SELL)
      trendText = "SELL TREND";

   string state = "STOPPED";

   if(TradingEnabled)
   {
      if(CountEAOpenPositions() > 0)
         state = "HOLDING TRADE";
      else
         state = "SCANNING / CONTINUING TREND";
   }

   Comment(
      "M1 TREND CONTINUATION SCALPER AI v5\n",
      "Symbol: ", _Symbol, "\n",
      "TIMEFRAME: M1 ONLY\n",
      "Status: ", state, "\n",
      "Trend: ", trendText, "\n",
      "Open Positions: ",
      CountEAOpenPositions(), "\n",
      "Consecutive Losses: ",
      ConsecutiveLosses, "\n",
      "Confirmation: ",
      DoubleToString(SignalThreshold, 0),
      "/100\n",
      "Risk/Reward: 1:",
      DoubleToString(RiskRewardRatio, 1)
   );
}//==================================================================
// DAILY STATISTICS
//==================================================================

void UpdateDailyStatistics()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > PeakEquity)
      PeakEquity = equity;
}

//==================================================================
// DAILY RESET
//==================================================================

void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime now;

   TimeToStruct(
      TimeCurrent(),
      now
   );

   int currentDayKey =
      now.year * 10000 +
      now.mon * 100 +
      now.day;

   if(currentDayKey != LastTradingDayKey)
   {
      LastTradingDayKey =
         currentDayKey;

      DayStartBalance =
         AccountInfoDouble(
            ACCOUNT_BALANCE
         );

      PeakEquity =
         AccountInfoDouble(
            ACCOUNT_EQUITY
         );

      ConsecutiveLosses = 0;

      Print("NEW TRADING DAY.");
      Print("Daily protection statistics reset.");
   }
}

//==================================================================
// DAILY LOSS PROTECTION
//==================================================================

bool DailyLossProtection()
{
   if(DayStartBalance <= 0.0)
      return(true);

   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY
      );

   double lossPercent =
      ((DayStartBalance - equity)
       / DayStartBalance) * 100.0;

   if(lossPercent >= DailyLossLimitPercent)
   {
      Print(
         "Daily loss protection active: ",
         DoubleToString(
            lossPercent,
            2
         ),
         "%"
      );

      return(false);
   }

   return(true);
}

//==================================================================
// DRAWDOWN PROTECTION
//==================================================================

bool DrawdownProtection()
{
   if(PeakEquity <= 0.0)
      return(true);

   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY
      );

   double drawdownPercent =
      ((PeakEquity - equity)
       / PeakEquity) * 100.0;

   if(drawdownPercent >= MaximumDrawdownPercent)
   {
      Print(
         "Maximum drawdown protection active: ",
         DoubleToString(
            drawdownPercent,
            2
         ),
         "%"
      );

      return(false);
   }

   return(true);
}

//==================================================================
// CONSECUTIVE LOSS PROTECTION
//==================================================================

bool ConsecutiveLossProtection()
{
   if(MaximumConsecutiveLosses <= 0)
      return(true);

   if(ConsecutiveLosses >=
      MaximumConsecutiveLosses)
   {
      Print(
         "Maximum consecutive losses reached: ",
         ConsecutiveLosses
      );

      return(false);
   }

   return(true);
}

//==================================================================
// CAN TRADE
//==================================================================

bool CanTrade()
{
   if(!TradingEnabled)
      return(false);

   if(!TerminalInfoInteger(
         TERMINAL_TRADE_ALLOWED))
      return(false);

   if(!MQLInfoInteger(
         MQL_TRADE_ALLOWED))
      return(false);

   if(!DailyLossProtection())
      return(false);

   if(!DrawdownProtection())
      return(false);

   if(!ConsecutiveLossProtection())
      return(false);

   return(true);
}

//==================================================================
// LOT NORMALIZATION
//==================================================================

double NormalizeLot(double lots)
{
   double minimumLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double brokerMaximumLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double lotStep =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   if(lotStep <= 0.0)
      lotStep = minimumLot;

   double maximumAllowed =
      MathMin(
         brokerMaximumLot,
         MaximumLotSize
      );

   lots =
      MathMax(
         lots,
         minimumLot
      );

   lots =
      MathMin(
         lots,
         maximumAllowed
      );

   lots =
      MathFloor(
         lots / lotStep
      ) * lotStep;

   if(lots < minimumLot)
      lots = minimumLot;

   int digits = 2;

   if(lotStep >= 1.0)
      digits = 0;
   else if(lotStep >= 0.1)
      digits = 1;
   else if(lotStep >= 0.01)
      digits = 2;
   else
      digits = 3;

   return NormalizeDouble(
      lots,
      digits
   );
}

//==================================================================
// DYNAMIC LOT
//==================================================================

double CalculateDynamicLot()
{
   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );

   double rawLot =
      balance * LotMultiplier;

   return NormalizeLot(rawLot);
}

//==================================================================
// COUNT EA POSITIONS
//==================================================================

int CountEAOpenPositions()
{
   int count = 0;

   int total =
      PositionsTotal();

   for(int i = total - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      if(symbol == _Symbol &&
         (ulong)magic == MagicNumber)
      {
         count++;
      }
   }

   return(count);
}

//==================================================================
// EA EXPOSURE
//==================================================================

double GetEAExposureLots()
{
   double exposure = 0.0;

   int total =
      PositionsTotal();

   for(int i = total - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      if(symbol == _Symbol &&
         (ulong)magic == MagicNumber)
      {
         exposure +=
            PositionGetDouble(
               POSITION_VOLUME
            );
      }
   }

   return(exposure);
}

//==================================================================
// HIGHEST HIGH
//==================================================================

double GetHighestHigh(
   ENUM_TIMEFRAMES timeframe,
   int startShift,
   int count
)
{
   if(count <= 0)
      return(0.0);

   double highest =
      iHigh(
         _Symbol,
         timeframe,
         startShift
      );

   for(int i = 1;
       i < count;
       i++)
   {
      double value =
         iHigh(
            _Symbol,
            timeframe,
            startShift + i
         );

      if(value > highest)
         highest = value;
   }

   return(highest);
}

//==================================================================
// LOWEST LOW
//==================================================================

double GetLowestLow(
   ENUM_TIMEFRAMES timeframe,
   int startShift,
   int count
)
{
   if(count <= 0)
      return(0.0);

   double lowest =
      iLow(
         _Symbol,
         timeframe,
         startShift
      );

   for(int i = 1;
       i < count;
       i++)
   {
      double value =
         iLow(
            _Symbol,
            timeframe,
            startShift + i
         );

      if(value < lowest)
         lowest = value;
   }

   return(lowest);
}

//==================================================================
// BULLISH STRUCTURE
//==================================================================

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
   {
      return(true);
   }

   return(false);
}

//==================================================================
// BEARISH STRUCTURE
//==================================================================

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
   {
      return(true);
   }

   return(false);
}

//==================================================================
// CURRENT BULLISH MOMENTUM
//==================================================================

bool BullishMomentum()
{
   double open =
      iOpen(
         _Symbol,
         PERIOD_M1,
         0
      );

   double high =
      iHigh(
         _Symbol,
         PERIOD_M1,
         0
      );

   double low =
      iLow(
         _Symbol,
         PERIOD_M1,
         0
      );

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double range =
      high - low;

   if(range <= 0.0)
      return(false);

   double body =
      MathAbs(
         tick.bid - open
      );

   double bodyPercent =
      (body / range) * 100.0;

   if(tick.bid > open &&
      bodyPercent >= MinimumBodyPercent)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// CURRENT BEARISH MOMENTUM
//==================================================================

bool BearishMomentum()
{
   double open =
      iOpen(
         _Symbol,
         PERIOD_M1,
         0
      );

   double high =
      iHigh(
         _Symbol,
         PERIOD_M1,
         0
      );

   double low =
      iLow(
         _Symbol,
         PERIOD_M1,
         0
      );

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double range =
      high - low;

   if(range <= 0.0)
      return(false);

   double body =
      MathAbs(
         tick.bid - open
      );

   double bodyPercent =
      (body / range) * 100.0;

   if(tick.bid < open &&
      bodyPercent >= MinimumBodyPercent)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// BULLISH CONTINUATION BREAKOUT
//==================================================================

bool BullishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double recentHigh =
      GetHighestHigh(
         PERIOD_M1,
         1,
         BreakoutLookback
      );

   if(tick.ask > recentHigh)
      return(true);

   return(false);
}

//==================================================================
// BEARISH CONTINUATION BREAKOUT
//==================================================================

bool BearishContinuationBreakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double recentLow =
      GetLowestLow(
         PERIOD_M1,
         1,
         BreakoutLookback
      );

   if(tick.bid < recentLow)
      return(true);

   return(false);
}//==================================================================
// BULLISH REVERSE BREAKOUT
//==================================================================
//
// Used ONLY when the current trend is BUY.
//
// Price must break below the recent M1 lows.
// A single opposite candle is NOT enough.
//
//==================================================================

bool BullishReverseBreakout()
{
   if(CurrentTrend != TREND_BUY)
      return(false);

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double recentLow =
      GetLowestLow(
         PERIOD_M1,
         1,
         ReverseBreakoutLookback
      );

   if(tick.bid < recentLow)
      return(true);

   return(false);
}

//==================================================================
// BEARISH REVERSE BREAKOUT
//==================================================================
//
// Used ONLY when the current trend is SELL.
//
// Price must break above recent M1 highs.
// A single opposite candle is NOT enough.
//
//==================================================================

bool BearishReverseBreakout()
{
   if(CurrentTrend != TREND_SELL)
      return(false);

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return(false);

   double recentHigh =
      GetHighestHigh(
         PERIOD_M1,
         1,
         ReverseBreakoutLookback
      );

   if(tick.ask > recentHigh)
      return(true);

   return(false);
}

//==================================================================
// INITIAL TREND DETECTION
//==================================================================

int DetectInitialTrend()
{
   bool bullish =
      IsBullishStructure();

   bool bearish =
      IsBearishStructure();

   if(bullish && !bearish)
      return(TREND_BUY);

   if(bearish && !bullish)
      return(TREND_SELL);

   return(TREND_NONE);
}

//==================================================================
// UPDATE TREND STATE
//==================================================================

void UpdateTrendState()
{
   //==============================================================
   // IF NO TREND YET
   //==============================================================

   if(CurrentTrend == TREND_NONE)
   {
      CurrentTrend =
         DetectInitialTrend();

      return;
   }

   //==============================================================
   // BUY TREND
   //==============================================================
   //
   // Stay BUY until a genuine bearish reverse breakout occurs.
   //
   //==============================================================

   if(CurrentTrend == TREND_BUY)
   {
      if(BullishReverseBreakout())
      {
         CurrentTrend = TREND_SELL;

         Print(
            "=========================================="
         );

         Print(
            "BEARISH REVERSE BREAKOUT DETECTED."
         );

         Print(
            "TREND CHANGED: BUY -> SELL"
         );

         Print(
            "M1 scanner will now follow SELL trend."
         );

         Print(
            "=========================================="
         );
      }

      return;
   }

   //==============================================================
   // SELL TREND
   //==============================================================

   if(CurrentTrend == TREND_SELL)
   {
      if(BearishReverseBreakout())
      {
         CurrentTrend = TREND_BUY;

         Print(
            "=========================================="
         );

         Print(
            "BULLISH REVERSE BREAKOUT DETECTED."
         );

         Print(
            "TREND CHANGED: SELL -> BUY"
         );

         Print(
            "M1 scanner will now follow BUY trend."
         );

         Print(
            "=========================================="
         );
      }

      return;
   }
}

//==================================================================
// BUY SCORE
//==================================================================

double GetBuyScore()
{
   double score = 0.0;

   if(CurrentTrend != TREND_BUY)
      return(score);

   if(IsBullishStructure())
      score += 25.0;

   if(BullishMomentum())
      score += 30.0;

   MqlTick tick;

   if(SymbolInfoTick(
         _Symbol,
         tick))
   {
      double currentOpen =
         iOpen(
            _Symbol,
            PERIOD_M1,
            0
         );

      if(tick.bid > currentOpen)
         score += 20.0;
   }

   if(BullishContinuationBreakout())
      score += 25.0;

   return(score);
}

//==================================================================
// SELL SCORE
//==================================================================

double GetSellScore()
{
   double score = 0.0;

   if(CurrentTrend != TREND_SELL)
      return(score);

   if(IsBearishStructure())
      score += 25.0;

   if(BearishMomentum())
      score += 30.0;

   MqlTick tick;

   if(SymbolInfoTick(
         _Symbol,
         tick))
   {
      double currentOpen =
         iOpen(
            _Symbol,
            PERIOD_M1,
            0
         );

      if(tick.bid < currentOpen)
         score += 20.0;
   }

   if(BearishContinuationBreakout())
      score += 25.0;

   return(score);
}

//==================================================================
// CHECK FOR ENTRY
//==================================================================

void CheckForEntry()
{
   //==============================================================
   // ONE POSITION AT A TIME
   //==============================================================

   if(CountEAOpenPositions() >=
      MaximumOpenPositions)
   {
      return;
   }

   if(!CanTrade())
      return;

   //==============================================================
   // MUST HAVE A TREND
   //==============================================================

   if(CurrentTrend == TREND_NONE)
      return;

   double buyScore =
      GetBuyScore();

   double sellScore =
      GetSellScore();

   //==============================================================
   // BUY
   //==============================================================

   if(CurrentTrend == TREND_BUY &&
      buyScore >= SignalThreshold)
   {
      Print(
         "BUY CONTINUATION CONFIRMED: ",
         DoubleToString(
            buyScore,
            0
         ),
         "/100"
      );

      OpenBuy();

      return;
   }

   //==============================================================
   // SELL
   //==============================================================

   if(CurrentTrend == TREND_SELL &&
      sellScore >= SignalThreshold)
   {
      Print(
         "SELL CONTINUATION CONFIRMED: ",
         DoubleToString(
            sellScore,
            0
         ),
         "/100"
      );

      OpenSell();

      return;
   }
}

//==================================================================
// OPEN BUY
//==================================================================

bool OpenBuy()
{
   if(CountEAOpenPositions() >=
      MaximumOpenPositions)
   {
      return(false);
   }

   double lot =
      CalculateDynamicLot();

   if(lot <= 0.0)
      return(false);

   double exposure =
      GetEAExposureLots();

   if(MaximumEAExposureLots > 0.0 &&
      exposure + lot >
      MaximumEAExposureLots)
   {
      Print(
         "BUY blocked by EA exposure limit."
      );

      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
   {
      return(false);
   }

   //==============================================================
   // STRUCTURE-BASED STOP
   //==============================================================

   double swingLow =
      GetLowestLow(
         PERIOD_M1,
         1,
         StructureLookback
      );

   double sl =
      swingLow -
      (SLBufferPoints * _Point);

   double riskDistance =
      tick.ask - sl;

   if(riskDistance <= 0.0)
      return(false);

   // Broker minimum stop distance
   double minimumStopDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   if(riskDistance <
      minimumStopDistance)
   {
      sl =
         tick.ask -
         minimumStopDistance;

      riskDistance =
         tick.ask - sl;
   }

   //==============================================================
   // RISK/REWARD TP
   //==============================================================

   double tp =
      tick.ask +
      (riskDistance *
       RiskRewardRatio);

   sl =
      NormalizeDouble(
         sl,
         _Digits
      );

   tp =
      NormalizeDouble(
         tp,
         _Digits
      );

   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M1 TREND BUY"
      );

   if(!result)
   {
      Print(
         "BUY FAILED: ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );

      return(false);
   }

   Print(
      "=========================================="
   );

   Print(
      "BUY OPENED - TREND CONTINUATION"
   );

   Print(
      "Lot: ",
      DoubleToString(
         lot,
         2
      )
   );

   Print(
      "Entry: ",
      DoubleToString(
         tick.ask,
         _Digits
      )
   );

   Print(
      "SL: ",
      DoubleToString(
         sl,
         _Digits
      )
   );

   Print(
      "TP: ",
      DoubleToString(
         tp,
         _Digits
      )
   );

   Print(
      "Risk/Reward: 1:",
      DoubleToString(
         RiskRewardRatio,
         1
      )
   );

   Print(
      "Will continue BUYING while BUY trend remains."
   );

   Print(
      "=========================================="
   );

   return(true);
}

//==================================================================
// OPEN SELL
//==================================================================

bool OpenSell()
{
   if(CountEAOpenPositions() >=
      MaximumOpenPositions)
   {
      return(false);
   }

   double lot =
      CalculateDynamicLot();

   if(lot <= 0.0)
      return(false);

   double exposure =
      GetEAExposureLots();

   if(MaximumEAExposureLots > 0.0 &&
      exposure + lot >
      MaximumEAExposureLots)
   {
      Print(
         "SELL blocked by EA exposure limit."
      );

      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
   {
      return(false);
   }

   //==============================================================
   // STRUCTURE-BASED STOP
   //==============================================================

   double swingHigh =
      GetHighestHigh(
         PERIOD_M1,
         1,
         StructureLookback
      );

   double sl =
      swingHigh +
      (SLBufferPoints * _Point);

   double riskDistance =
      sl - tick.bid;

   if(riskDistance <= 0.0)
      return(false);

   // Broker minimum stop distance
   double minimumStopDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   if(riskDistance <
      minimumStopDistance)
   {
      sl =
         tick.bid +
         minimumStopDistance;

      riskDistance =
         sl - tick.bid;
   }

   //==============================================================
   // RISK/REWARD TP
   //==============================================================

   double tp =
      tick.bid -
      (riskDistance *
       RiskRewardRatio);

   sl =
      NormalizeDouble(
         sl,
         _Digits
      );

   tp =
      NormalizeDouble(
         tp,
         _Digits
      );

   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M1 TREND SELL"
      );

   if(!result)
   {
      Print(
         "SELL FAILED: ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );

      return(false);
   }

   Print(
      "=========================================="
   );

   Print(
      "SELL OPENED - TREND CONTINUATION"
   );

   Print(
      "Lot: ",
      DoubleToString(
         lot,
         2
      )
   );

   Print(
      "Entry: ",
      DoubleToString(
         tick.bid,
         _Digits
      )
   );

   Print(
      "SL: ",
      DoubleToString(
         sl,
         _Digits
      )
   );

   Print(
      "TP: ",
      DoubleToString(
         tp,
         _Digits
      )
   );

   Print(
      "Risk/Reward: 1:",
      DoubleToString(
         RiskRewardRatio,
         1
      )
   );

   Print(
      "Will continue SELLING while SELL trend remains."
   );

   Print(
      "=========================================="
   );

   return(true);
}

//==================================================================
// CONSECUTIVE LOSS TRACKING
//==================================================================

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket
)
{
   if(!HistoryDealSelect(
         dealTicket))
   {
      return;
   }

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

   if(symbol != _Symbol)
      return;

   if((ulong)magic != MagicNumber)
      return;

   long entryType =
      HistoryDealGetInteger(
         dealTicket,
         DEAL_ENTRY
      );

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

      Print(
         "LOSING TRADE CLOSED."
      );

      Print(
         "Consecutive losses: ",
         ConsecutiveLosses
      );
   }
   else if(netResult > 0.0)
   {
      ConsecutiveLosses = 0;

      Print(
         "PROFITABLE TRADE CLOSED."
      );

      Print(
         "Consecutive loss counter reset."
      );
   }
}

//==================================================================
// END OF M1_TREND_CONTINUATION_SCALPER_AI_v5
//==================================================================
