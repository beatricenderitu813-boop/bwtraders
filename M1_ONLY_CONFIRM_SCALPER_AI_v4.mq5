//+------------------------------------------------------------------+
//| M1_ONLY_CONFIRM_SCALPER_AI_v4.mq5                                |
//| M1 ONLY: Structure + Momentum + Breakout + Confirmation          |
//+------------------------------------------------------------------+
#property strict
#property version   "4.00"
#property description "M1-only confirmation scalping EA"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input bool   StartTradingOnAttach     = false;
input ulong  MagicNumber              = 26092026;

// Minimum confirmation required
input double SignalThreshold          = 70.0;

// Dynamic lot sizing
// Example: $10 = 0.01, $100 = 0.10, $1000 = 1.00
input double LotMultiplier            = 0.001;
input double MaximumLotSize           = 10.0;

// SL and TP
input int    StopLossPoints           = 100;
input int    TakeProfitPoints         = 150;

// One trade at a time
input int    MaximumOpenPositions     = 1;
input double MaximumEAExposureLots    = 10.0;

// M1 structure
input int    StructureLookback        = 3;

// M1 breakout
input int    BreakoutLookback         = 5;

// Current M1 candle momentum
input double MinimumBodyPercent       = 55.0;

// Protection
input double DailyLossLimitPercent    = 2.0;
input double MaximumDrawdownPercent   = 5.0;
input int    MaximumConsecutiveLosses = 3;

input ulong  SlippagePoints           = 20;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

bool   TradingEnabled = false;

double DayStartBalance = 0.0;
double PeakEquity      = 0.0;

int    ConsecutiveLosses = 0;
int    LastTradingDayKey = -1;

// TRUE after SL/TP closes a trade.
// The EA must see the old signal disappear before another
// trade can be opened.
bool WaitingForFreshConfirmation = false;

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

int    CountEAOpenPositions();
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

bool BullishBreakout();
bool BearishBreakout();

void GetCurrentSignal(
   int &signal,
   double &buyScore,
   double &sellScore
);

bool SignalIsNeutral();

void CheckForNewEntry();

bool OpenBuy();
bool OpenSell();

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

   WaitingForFreshConfirmation = false;

   TradingEnabled = StartTradingOnAttach;

   CreateControlButtons();

   Print("==========================================");
   Print("M1 ONLY CONFIRM SCALPER AI v4 STARTED");
   Print("Symbol: ", _Symbol);
   Print("Trading timeframe: M1 ONLY");
   Print("No M5 filter");
   Print("No H1 filter");
   Print("Fresh confirmation system: ENABLED");
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

   UpdateStatus();

   if(!TradingEnabled)
      return;

   CheckForNewEntry();
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

   // When our position is completely closed,
   // force the scanner to wait for a fresh signal.
   if(CountEAOpenPositions() == 0)
   {
      WaitingForFreshConfirmation = true;

      Print("------------------------------------------");
      Print("TRADE CLOSED");
      Print("Old signal must clear first.");
      Print("Waiting for FRESH M1 confirmation.");
      Print("------------------------------------------");
   }
}

//==================================================================
// CHART BUTTON EVENTS
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

      Print("M1 SCALPER STARTED.");
   }

   if(sparam == "M1_STOP_BUTTON")
   {
      TradingEnabled = false;

      Print("M1 SCALPER STOPPED.");
      Print("Existing trade will NOT be forcibly closed.");
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
   int positions =
      CountEAOpenPositions();

   string state;

   if(!TradingEnabled)
      state = "STOPPED";
   else if(positions > 0)
      state = "HOLDING TRADE";
   else if(WaitingForFreshConfirmation)
      state = "WAITING FOR FRESH SIGNAL";
   else
      state = "SCANNING M1";

   Comment(
      "M1 ONLY CONFIRM SCALPER AI v4\n",
      "Symbol: ", _Symbol, "\n",
      "TIMEFRAME: M1 ONLY\n",
      "Status: ", state, "\n",
      "Open Positions: ", positions, "\n",
      "Consecutive Losses: ",
      ConsecutiveLosses, "\n",
      "Confirmation: ",
      DoubleToString(SignalThreshold, 0),
      "/100\n",
      "SL: ", StopLossPoints,
      " points\n",
      "TP: ", TakeProfitPoints,
      " points"
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

      WaitingForFreshConfirmation = false;

      Print("NEW TRADING DAY.");
      Print("Daily statistics reset.");
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
// MAXIMUM DRAWDOWN
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

   if(drawdownPercent >=
      MaximumDrawdownPercent)
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
// CONSECUTIVE LOSSES
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
// GENERAL TRADE PERMISSION
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

   int volumeDigits = 2;

   if(lotStep == 1.0)
      volumeDigits = 0;
   else if(lotStep == 0.1)
      volumeDigits = 1;
   else if(lotStep == 0.01)
      volumeDigits = 2;
   else if(lotStep == 0.001)
      volumeDigits = 3;

   return NormalizeDouble(
      lots,
      volumeDigits
   );
}

//==================================================================
// DYNAMIC LOT SIZE
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
// BULLISH M1 STRUCTURE
//==================================================================
//
// Requires the last 3 CLOSED M1 candles to show:
// Higher High + Higher Low progression.
//
// Candle 1 = most recently closed
// Candle 2 = previous
// Candle 3 = previous again
//
//==================================================================

bool IsBullishStructure()
{
   if(StructureLookback < 3)
      return(false);

   double high1 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         1
      );

   double high2 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         2
      );

   double high3 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         3
      );

   double low1 =
      iLow(
         _Symbol,
         PERIOD_M1,
         1
      );

   double low2 =
      iLow(
         _Symbol,
         PERIOD_M1,
         2
      );

   double low3 =
      iLow(
         _Symbol,
         PERIOD_M1,
         3
      );

   if(high1 > high2 &&
      high2 > high3 &&
      low1 > low2 &&
      low2 > low3)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// BEARISH M1 STRUCTURE
//==================================================================

bool IsBearishStructure()
{
   if(StructureLookback < 3)
      return(false);

   double high1 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         1
      );

   double high2 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         2
      );

   double high3 =
      iHigh(
         _Symbol,
         PERIOD_M1,
         3
      );

   double low1 =
      iLow(
         _Symbol,
         PERIOD_M1,
         1
      );

   double low2 =
      iLow(
         _Symbol,
         PERIOD_M1,
         2
      );

   double low3 =
      iLow(
         _Symbol,
         PERIOD_M1,
         3
      );

   if(high1 < high2 &&
      high2 < high3 &&
      low1 < low2 &&
      low2 < low3)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// CURRENT M1 BULLISH MOMENTUM
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
      bodyPercent >=
      MinimumBodyPercent)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// CURRENT M1 BEARISH MOMENTUM
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
      bodyPercent >=
      MinimumBodyPercent)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// BULLISH M1 BREAKOUT
//==================================================================

bool BullishBreakout()
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
// BEARISH M1 BREAKOUT
//==================================================================

bool BearishBreakout()
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
// CURRENT M1 SIGNAL
//==================================================================
//
// BUY SCORE
// Structure       = 25
// Momentum        = 25
// Breakout        = 15
// Price position  = 10
// TOTAL           = 75
//
// SELL uses the exact opposite conditions.
//
// Minimum required = 70
//==================================================================

void GetCurrentSignal(
   int &signal,
   double &buyScore,
   double &sellScore
)
{
   signal = 0;

   buyScore = 0.0;
   sellScore = 0.0;

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick))
      return;

   double currentOpen =
      iOpen(
         _Symbol,
         PERIOD_M1,
         0
      );

   //==============================================================
   // STRUCTURE
   //==============================================================

   bool bullishStructure =
      IsBullishStructure();

   bool bearishStructure =
      IsBearishStructure();

   //==============================================================
   // MOMENTUM
   //==============================================================

   bool bullishMomentum =
      BullishMomentum();

   bool bearishMomentum =
      BearishMomentum();

   //==============================================================
   // BREAKOUT
   //==============================================================

   bool bullishBreakout =
      BullishBreakout();

   bool bearishBreakout =
      BearishBreakout();

   //==============================================================
   // BUY SCORE
   //==============================================================

   if(bullishStructure)
      buyScore += 25.0;

   if(bullishMomentum)
      buyScore += 25.0;

   if(bullishBreakout)
      buyScore += 15.0;

   if(tick.bid > currentOpen)
      buyScore += 10.0;

   //==============================================================
   // SELL SCORE
   //==============================================================

   if(bearishStructure)
      sellScore += 25.0;

   if(bearishMomentum)
      sellScore += 25.0;

   if(bearishBreakout)
      sellScore += 15.0;

   if(tick.bid < currentOpen)
      sellScore += 10.0;

   //==============================================================
   // FINAL DECISION
   //==============================================================

   if(buyScore >= SignalThreshold &&
      buyScore > sellScore)
   {
      signal = 1;
   }
   else if(sellScore >= SignalThreshold &&
           sellScore > buyScore)
   {
      signal = -1;
   }
}

//==================================================================
// CHECK WHETHER OLD SIGNAL HAS CLEARED
//==================================================================

bool SignalIsNeutral()
{
   int signal = 0;

   double buyScore = 0.0;
   double sellScore = 0.0;

   GetCurrentSignal(
      signal,
      buyScore,
      sellScore
   );

   // Both sides must be below the trading threshold.
   // This means the old confirmation has disappeared.
   if(buyScore < SignalThreshold &&
      sellScore < SignalThreshold)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// MAIN ENTRY LOGIC
//==================================================================

void CheckForNewEntry()
{
   //==============================================================
   // ONE TRADE AT A TIME
   //==============================================================

   if(CountEAOpenPositions() >=
      MaximumOpenPositions)
   {
      return;
   }

   //==============================================================
   // SAFETY CHECKS
   //==============================================================

   if(!CanTrade())
      return;

   //==============================================================
   // FRESH SIGNAL REQUIREMENT
   //==============================================================

   if(WaitingForFreshConfirmation)
   {
      // Do not trade while the old signal remains active.
      if(!SignalIsNeutral())
         return;

      // Old signal has disappeared.
      // The scanner is now allowed to look for a completely
      // fresh confirmation.
      WaitingForFreshConfirmation = false;

      Print(
         "OLD SIGNAL CLEARED."
      );

      Print(
         "M1 scanner is looking for a FRESH setup."
      );
   }

   //==============================================================
   // SCAN M1
   //==============================================================

   int signal = 0;

   double buyScore = 0.0;
   double sellScore = 0.0;

   GetCurrentSignal(
      signal,
      buyScore,
      sellScore
   );

   //==============================================================
   // BUY
   //==============================================================

   if(signal == 1)
   {
      Print(
         "M1 BUY CONFIRMATION: ",
         DoubleToString(
            buyScore,
            0
         ),
         "/100"
      );

      if(OpenBuy())
      {
         WaitingForFreshConfirmation = false;
      }

      return;
   }

   //==============================================================
   // SELL
   //==============================================================

   if(signal == -1)
   {
      Print(
         "M1 SELL CONFIRMATION: ",
         DoubleToString(
            sellScore,
            0
         ),
         "/100"
      );

      if(OpenSell())
      {
         WaitingForFreshConfirmation = false;
      }

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
      Print(
         "Could not obtain BUY price."
      );

      return(false);
   }

   double minimumDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   double slDistance =
      MathMax(
         StopLossPoints * _Point,
         minimumDistance
      );

   double tpDistance =
      MathMax(
         TakeProfitPoints * _Point,
         minimumDistance
      );

   double sl =
      tick.ask - slDistance;

   double tp =
      tick.ask + tpDistance;

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
         "M1 CONFIRM BUY"
      );

   if(!result)
   {
      Print(
         "BUY FAILED. Retcode: ",
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
      "BUY OPENED"
   );

   Print(
      "Lot: ",
      DoubleToString(
         lot,
         2
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
      "Trade will HOLD until SL or TP."
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
      Print(
         "Could not obtain SELL price."
      );

      return(false);
   }

   double minimumDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   double slDistance =
      MathMax(
         StopLossPoints * _Point,
         minimumDistance
      );

   double tpDistance =
      MathMax(
         TakeProfitPoints * _Point,
         minimumDistance
      );

   double sl =
      tick.bid + slDistance;

   double tp =
      tick.bid - tpDistance;

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
         "M1 CONFIRM SELL"
      );

   if(!result)
   {
      Print(
         "SELL FAILED. Retcode: ",
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
      "SELL OPENED"
   );

   Print(
      "Lot: ",
      DoubleToString(
         lot,
         2
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
      "Trade will HOLD until SL or TP."
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
// END OF M1_ONLY_CONFIRM_SCALPER_AI_v4
//==================================================================
