//+------------------------------------------------------------------+
//| M5_M1_CONFIRM_SCALPER_AI_v3.mq5                                 |
//| M5 direction + M1 confirmation scalping EA                       |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "M5 market direction + M1 real-time confirmation scalper"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input bool   StartTradingOnAttach      = false;
input ulong  MagicNumber               = 26092026;

input double SignalThreshold           = 70.0;

input double LotMultiplier             = 0.001;
input double MaximumLotSize            = 10.0;

input int    StopLossPoints            = 100;
input int    TakeProfitPoints          = 150;

input int    MaximumOpenPositions      = 1;
input double MaximumEAExposureLots     = 10.0;

input int    M1StructureLookback       = 5;
input int    M1BreakoutLookback        = 5;
input int    M5StructureLookback       = 5;

input double MinimumM1BodyPercent      = 55.0;

input double DailyLossLimitPercent     = 2.0;
input double MaximumDrawdownPercent    = 5.0;
input int    MaximumConsecutiveLosses  = 3;

input ulong  SlippagePoints            = 20;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

bool     TradingEnabled = false;

double   DayStartBalance = 0.0;
double   PeakEquity      = 0.0;

int      ConsecutiveLosses = 0;

int      LastTradingDayKey = -1;

// After a trade closes, this prevents the old signal
// from immediately opening another trade.
bool     WaitingForFreshConfirmation = false;

//==================================================================
// FUNCTION DECLARATIONS
//==================================================================

void   CreateControlButtons();
void   DeleteControlButtons();
void   UpdateStatus();

void   UpdateDailyStatistics();
void   ResetDailyStatisticsIfNeeded();

bool   DailyLossProtection();
bool   DrawdownProtection();
bool   ConsecutiveLossProtection();
bool   CanTrade();

double NormalizeLot(double lots);
double CalculateDynamicLot();

int    CountEAOpenPositions();
double GetEAExposureLots();

double GetHighestHigh(ENUM_TIMEFRAMES timeframe,
                      int startShift,
                      int count);

double GetLowestLow(ENUM_TIMEFRAMES timeframe,
                     int startShift,
                     int count);

bool   IsBullishM5Bias();
bool   IsBearishM5Bias();

bool   IsBullishM1Structure();
bool   IsBearishM1Structure();

bool   BullishM1Momentum();
bool   BearishM1Momentum();

bool   BullishM1Breakout();
bool   BearishM1Breakout();

void   GetCurrentSignal(int &signal,
                        double &buyScore,
                        double &sellScore);

bool   SignalIsNeutral();

void   CheckForNewEntry();

bool   OpenBuy();
bool   OpenSell();

void   UpdateConsecutiveLossesFromDeal(ulong dealTicket);

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   PeakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   LastTradingDayKey =
      now.year * 10000 +
      now.mon  * 100 +
      now.day;

   ConsecutiveLosses = 0;

   WaitingForFreshConfirmation = false;

   TradingEnabled = StartTradingOnAttach;

   CreateControlButtons();

   Print("M5_M1_CONFIRM_SCALPER_AI_v3 initialized.");
   Print("Symbol: ", _Symbol);
   Print("Entry timeframe: M1");
   Print("Direction timeframe: M5");
   Print("Fresh confirmation protection: ENABLED");

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
// MAIN TICK FUNCTION
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
   const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(trans.deal == 0)
      return;

   UpdateConsecutiveLossesFromDeal(trans.deal);

   // A completed EA position means the next trade must use
   // a fresh confirmation.
   if(CountEAOpenPositions() == 0)
   {
      WaitingForFreshConfirmation = true;

      Print("Previous trade closed.");
      Print("Waiting for a FRESH confirmation before next entry.");
   }
}

//==================================================================
// CHART BUTTON EVENTS
//==================================================================

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "M5M1_START_BUTTON")
   {
      TradingEnabled = true;

      Print("M5/M1 SCALPER STARTED.");
   }

   if(sparam == "M5M1_STOP_BUTTON")
   {
      TradingEnabled = false;

      Print("M5/M1 SCALPER STOPPED.");
      Print("Existing trades are NOT forcibly closed.");
   }

   UpdateStatus();
}

//==================================================================
// BUTTON CREATION
//==================================================================

void CreateControlButtons()
{
   ObjectDelete(0, "M5M1_START_BUTTON");
   ObjectDelete(0, "M5M1_STOP_BUTTON");

   ObjectCreate(
      0,
      "M5M1_START_BUTTON",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "M5M1_START_BUTTON",
      OBJPROP_XDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M5M1_START_BUTTON",
      OBJPROP_YDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M5M1_START_BUTTON",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "M5M1_START_BUTTON",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "M5M1_START_BUTTON",
      OBJPROP_TEXT,
      "START"
   );

   ObjectCreate(
      0,
      "M5M1_STOP_BUTTON",
      OBJ_BUTTON,
      0,
      0,
      0
   );

   ObjectSetInteger(
      0,
      "M5M1_STOP_BUTTON",
      OBJPROP_XDISTANCE,
      130
   );

   ObjectSetInteger(
      0,
      "M5M1_STOP_BUTTON",
      OBJPROP_YDISTANCE,
      20
   );

   ObjectSetInteger(
      0,
      "M5M1_STOP_BUTTON",
      OBJPROP_XSIZE,
      100
   );

   ObjectSetInteger(
      0,
      "M5M1_STOP_BUTTON",
      OBJPROP_YSIZE,
      30
   );

   ObjectSetString(
      0,
      "M5M1_STOP_BUTTON",
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
   ObjectDelete(0, "M5M1_START_BUTTON");
   ObjectDelete(0, "M5M1_STOP_BUTTON");
}

//==================================================================
// STATUS DISPLAY
//==================================================================

void UpdateStatus()
{
   int positions = CountEAOpenPositions();

   string state;

   if(!TradingEnabled)
      state = "STOPPED";
   else if(positions > 0)
      state = "HOLDING TRADE";
   else if(WaitingForFreshConfirmation)
      state = "WAITING FOR FRESH SIGNAL";
   else
      state = "SCANNING M5 + M1";

   Comment(
      "M5/M1 CONFIRM SCALPER AI v3\n",
      "Symbol: ", _Symbol, "\n",
      "Direction: M5\n",
      "Entry: M1 REAL-TIME\n",
      "Status: ", state, "\n",
      "Open Positions: ", positions, "\n",
      "Consecutive Losses: ", ConsecutiveLosses, "\n",
      "Threshold: ", DoubleToString(SignalThreshold, 0), "/100\n",
      "SL: ", StopLossPoints, " points\n",
      "TP: ", TakeProfitPoints, " points"
   );
}//==================================================================
// DAILY STATISTICS
//==================================================================

void UpdateDailyStatistics()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > PeakEquity)
      PeakEquity = equity;
}

//==================================================================
// DAILY RESET
//==================================================================

void ResetDailyStatisticsIfNeeded()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int currentDayKey =
      now.year * 10000 +
      now.mon  * 100 +
      now.day;

   if(currentDayKey != LastTradingDayKey)
   {
      LastTradingDayKey = currentDayKey;

      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      PeakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);

      ConsecutiveLosses = 0;

      WaitingForFreshConfirmation = false;

      Print("New trading day detected.");
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

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double lossPercent =
      ((DayStartBalance - equity) /
       DayStartBalance) * 100.0;

   if(lossPercent >= DailyLossLimitPercent)
   {
      Print(
         "Daily loss protection active: ",
         DoubleToString(lossPercent, 2),
         "%"
      );

      return(false);
   }

   return(true);
}

//==================================================================
// MAXIMUM DRAWDOWN PROTECTION
//==================================================================

bool DrawdownProtection()
{
   if(PeakEquity <= 0.0)
      return(true);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double drawdownPercent =
      ((PeakEquity - equity) /
       PeakEquity) * 100.0;

   if(drawdownPercent >= MaximumDrawdownPercent)
   {
      Print(
         "Maximum drawdown protection active: ",
         DoubleToString(drawdownPercent, 2),
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

   if(ConsecutiveLosses >= MaximumConsecutiveLosses)
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

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
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
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double maximumBrokerLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lotStep =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0.0)
      lotStep = minimumLot;

   double maximumAllowed =
      MathMin(maximumBrokerLot, MaximumLotSize);

   lots = MathMax(lots, minimumLot);
   lots = MathMin(lots, maximumAllowed);

   lots =
      MathFloor(lots / lotStep) * lotStep;

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

   return NormalizeDouble(lots, volumeDigits);
}

//==================================================================
// DYNAMIC LOT SIZE
//==================================================================

double CalculateDynamicLot()
{
   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

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

   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

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

   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol &&
         (ulong)magic == MagicNumber)
      {
         exposure +=
            PositionGetDouble(POSITION_VOLUME);
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
   int count)
{
   if(count <= 0)
      return(0.0);

   double highest =
      iHigh(_Symbol, timeframe, startShift);

   for(int i = 1; i < count; i++)
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
   int count)
{
   if(count <= 0)
      return(0.0);

   double lowest =
      iLow(_Symbol, timeframe, startShift);

   for(int i = 1; i < count; i++)
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
// M5 BULLISH MARKET BIAS
//==================================================================

bool IsBullishM5Bias()
{
   double recentHigh =
      iHigh(_Symbol, PERIOD_M5, 1);

   double previousHigh =
      iHigh(_Symbol, PERIOD_M5, 2);

   double recentLow =
      iLow(_Symbol, PERIOD_M5, 1);

   double previousLow =
      iLow(_Symbol, PERIOD_M5, 2);

   if(recentHigh > previousHigh &&
      recentLow > previousLow)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// M5 BEARISH MARKET BIAS
//==================================================================

bool IsBearishM5Bias()
{
   double recentHigh =
      iHigh(_Symbol, PERIOD_M5, 1);

   double previousHigh =
      iHigh(_Symbol, PERIOD_M5, 2);

   double recentLow =
      iLow(_Symbol, PERIOD_M5, 1);

   double previousLow =
      iLow(_Symbol, PERIOD_M5, 2);

   if(recentHigh < previousHigh &&
      recentLow < previousLow)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// M1 BULLISH STRUCTURE
//==================================================================

bool IsBullishM1Structure()
{
   int shiftA = 1;
   int shiftB = 2;

   double highA =
      iHigh(_Symbol, PERIOD_M1, shiftA);

   double highB =
      iHigh(_Symbol, PERIOD_M1, shiftB);

   double lowA =
      iLow(_Symbol, PERIOD_M1, shiftA);

   double lowB =
      iLow(_Symbol, PERIOD_M1, shiftB);

   return(
      highA > highB &&
      lowA > lowB
   );
}

//==================================================================
// M1 BEARISH STRUCTURE
//==================================================================

bool IsBearishM1Structure()
{
   int shiftA = 1;
   int shiftB = 2;

   double highA =
      iHigh(_Symbol, PERIOD_M1, shiftA);

   double highB =
      iHigh(_Symbol, PERIOD_M1, shiftB);

   double lowA =
      iLow(_Symbol, PERIOD_M1, shiftA);

   double lowB =
      iLow(_Symbol, PERIOD_M1, shiftB);

   return(
      highA < highB &&
      lowA < lowB
   );
}

//==================================================================
// CURRENT M1 BULLISH MOMENTUM
//==================================================================

bool BullishM1Momentum()
{
   double open =
      iOpen(_Symbol, PERIOD_M1, 0);

   double high =
      iHigh(_Symbol, PERIOD_M1, 0);

   double low =
      iLow(_Symbol, PERIOD_M1, 0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return(false);

   double price = tick.bid;

   double range = high - low;

   if(range <= 0.0)
      return(false);

   double body =
      MathAbs(price - open);

   double bodyPercent =
      (body / range) * 100.0;

   return(
      price > open &&
      bodyPercent >= MinimumM1BodyPercent
   );
}

//==================================================================
// CURRENT M1 BEARISH MOMENTUM
//==================================================================

bool BearishM1Momentum()
{
   double open =
      iOpen(_Symbol, PERIOD_M1, 0);

   double high =
      iHigh(_Symbol, PERIOD_M1, 0);

   double low =
      iLow(_Symbol, PERIOD_M1, 0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return(false);

   double price = tick.bid;

   double range = high - low;

   if(range <= 0.0)
      return(false);

   double body =
      MathAbs(price - open);

   double bodyPercent =
      (body / range) * 100.0;

   return(
      price < open &&
      bodyPercent >= MinimumM1BodyPercent
   );
}

//==================================================================
// M1 BULLISH BREAKOUT
//==================================================================

bool BullishM1Breakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return(false);

   double resistance =
      GetHighestHigh(
         PERIOD_M1,
         1,
         M1BreakoutLookback
      );

   return(tick.ask > resistance);
}

//==================================================================
// M1 BEARISH BREAKOUT
//==================================================================

bool BearishM1Breakout()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return(false);

   double support =
      GetLowestLow(
         PERIOD_M1,
         1,
         M1BreakoutLookback
      );

   return(tick.bid < support);
}//==================================================================
// GET CURRENT SIGNAL
//==================================================================

void GetCurrentSignal(
   int &signal,
   double &buyScore,
   double &sellScore)
{
   signal = 0;

   buyScore  = 0.0;
   sellScore = 0.0;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double currentM1Open =
      iOpen(_Symbol, PERIOD_M1, 0);

   //==============================================================
   // M5 MARKET DIRECTION
   //==============================================================

   bool m5Bullish =
      IsBullishM5Bias();

   bool m5Bearish =
      IsBearishM5Bias();

   //==============================================================
   // M1 STRUCTURE
   //==============================================================

   bool m1BullishStructure =
      IsBullishM1Structure();

   bool m1BearishStructure =
      IsBearishM1Structure();

   //==============================================================
   // M1 CURRENT CANDLE MOMENTUM
   //==============================================================

   bool m1BullishMomentum =
      BullishM1Momentum();

   bool m1BearishMomentum =
      BearishM1Momentum();

   //==============================================================
   // M1 BREAKOUT
   //==============================================================

   bool m1BullishBreakout =
      BullishM1Breakout();

   bool m1BearishBreakout =
      BearishM1Breakout();

   //==============================================================
   // BUY SCORING
   //==============================================================

   if(m5Bullish)
      buyScore += 25.0;

   if(m1BullishStructure)
      buyScore += 25.0;

   if(m1BullishMomentum)
      buyScore += 25.0;

   if(m1BullishBreakout)
      buyScore += 15.0;

   if(tick.bid > currentM1Open)
      buyScore += 10.0;

   //==============================================================
   // SELL SCORING
   //==============================================================

   if(m5Bearish)
      sellScore += 25.0;

   if(m1BearishStructure)
      sellScore += 25.0;

   if(m1BearishMomentum)
      sellScore += 25.0;

   if(m1BearishBreakout)
      sellScore += 15.0;

   if(tick.bid < currentM1Open)
      sellScore += 10.0;

   //==============================================================
   // FINAL DIRECTION
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
// SIGNAL NEUTRAL CHECK
//==================================================================

bool SignalIsNeutral()
{
   int signal = 0;

   double buyScore  = 0.0;
   double sellScore = 0.0;

   GetCurrentSignal(
      signal,
      buyScore,
      sellScore
   );

   // The old signal must disappear completely.
   // This is what forces a fresh confirmation.
   if(buyScore < SignalThreshold &&
      sellScore < SignalThreshold)
   {
      return(true);
   }

   return(false);
}

//==================================================================
// CHECK FOR NEW ENTRY
//==================================================================

void CheckForNewEntry()
{
   //==============================================================
   // NEVER OPEN ANOTHER POSITION WHILE ONE IS ACTIVE
   //==============================================================

   if(CountEAOpenPositions() >= MaximumOpenPositions)
      return;

   //==============================================================
   // PROTECTIONS
   //==============================================================

   if(!CanTrade())
      return;

   //==============================================================
   // FRESH CONFIRMATION SYSTEM
   //==============================================================

   if(WaitingForFreshConfirmation)
   {
      if(SignalIsNeutral())
      {
         WaitingForFreshConfirmation = false;

         Print(
            "Old signal has cleared. ",
            "EA is now waiting for a NEW confirmation."
         );
      }
      else
      {
         return;
      }
   }

   //==============================================================
   // SCAN CURRENT MARKET
   //==============================================================

   int signal = 0;

   double buyScore  = 0.0;
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
         "FRESH BUY CONFIRMATION: ",
         DoubleToString(buyScore, 0),
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
         "FRESH SELL CONFIRMATION: ",
         DoubleToString(sellScore, 0),
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
   if(CountEAOpenPositions() >= MaximumOpenPositions)
      return(false);

   double lot =
      CalculateDynamicLot();

   if(lot <= 0.0)
      return(false);

   double currentExposure =
      GetEAExposureLots();

   if(MaximumEAExposureLots > 0.0 &&
      currentExposure + lot >
      MaximumEAExposureLots)
   {
      Print("BUY blocked by EA exposure limit.");
      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Could not obtain current tick for BUY.");
      return(false);
   }

   double minimumStopDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   double requestedSLDistance =
      StopLossPoints * _Point;

   double requestedTPDistance =
      TakeProfitPoints * _Point;

   double slDistance =
      MathMax(
         requestedSLDistance,
         minimumStopDistance
      );

   double tpDistance =
      MathMax(
         requestedTPDistance,
         minimumStopDistance
      );

   double sl =
      tick.ask - slDistance;

   double tp =
      tick.ask + tpDistance;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool sent =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M5 M1 FRESH BUY"
      );

   if(!sent)
   {
      Print(
         "BUY failed. Retcode: ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );

      return(false);
   }

   Print(
      "BUY OPENED | Lot=",
      DoubleToString(lot, 2),
      " | SL=",
      DoubleToString(sl, _Digits),
      " | TP=",
      DoubleToString(tp, _Digits)
   );

   return(true);
}

//==================================================================
// OPEN SELL
//==================================================================

bool OpenSell()
{
   if(CountEAOpenPositions() >= MaximumOpenPositions)
      return(false);

   double lot =
      CalculateDynamicLot();

   if(lot <= 0.0)
      return(false);

   double currentExposure =
      GetEAExposureLots();

   if(MaximumEAExposureLots > 0.0 &&
      currentExposure + lot >
      MaximumEAExposureLots)
   {
      Print("SELL blocked by EA exposure limit.");
      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Could not obtain current tick for SELL.");
      return(false);
   }

   double minimumStopDistance =
      (double)SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      ) * _Point;

   double requestedSLDistance =
      StopLossPoints * _Point;

   double requestedTPDistance =
      TakeProfitPoints * _Point;

   double slDistance =
      MathMax(
         requestedSLDistance,
         minimumStopDistance
      );

   double tpDistance =
      MathMax(
         requestedTPDistance,
         minimumStopDistance
      );

   double sl =
      tick.bid + slDistance;

   double tp =
      tick.bid - tpDistance;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool sent =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         "M5 M1 FRESH SELL"
      );

   if(!sent)
   {
      Print(
         "SELL failed. Retcode: ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );

      return(false);
   }

   Print(
      "SELL OPENED | Lot=",
      DoubleToString(lot, 2),
      " | SL=",
      DoubleToString(sl, _Digits),
      " | TP=",
      DoubleToString(tp, _Digits)
   );

   return(true);
}

//==================================================================
// CONSECUTIVE LOSS TRACKING
//==================================================================

void UpdateConsecutiveLossesFromDeal(
   ulong dealTicket)
{
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
         "Closed losing trade. ",
         "Consecutive losses = ",
         ConsecutiveLosses
      );
   }
   else if(netResult > 0.0)
   {
      ConsecutiveLosses = 0;

      Print(
         "Closed profitable trade. ",
         "Consecutive loss counter reset."
      );
   }
}

//==================================================================
// END OF EA
//==================================================================
