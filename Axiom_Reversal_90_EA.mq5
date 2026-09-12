//+------------------------------------------------------------------+
//|                  AXIOM REVERSAL 90 EA                            |
//|                  Version 1.00                                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Live M1 90 percent reversal EA"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

input double InpLotSize      = 0.01;       // Lot size per position
input int    InpMaxPositions = 10;         // Maximum EA positions
input double InpTrigger      = 90.0;       // Reversal trigger
input ulong  InpMagicNumber  = 26092026;   // EA magic number
input int    InpDeviation    = 20;         // Maximum deviation

//==================================================================
// GLOBAL VARIABLES
//==================================================================

bool     g_running      = false;
datetime g_currentBar   = 0;

double   g_buyPercent  = 50.0;
double   g_sellPercent = 50.0;

string g_buttonName   = "AXIOM_START_STOP";
string g_statusName   = "AXIOM_STATUS";
string g_progressName = "AXIOM_PROGRESS";

int g_lastDirection = 0;

//  1  = BUY
// -1  = SELL
//  0  = NONE

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);

   g_currentBar = iTime(_Symbol, PERIOD_M1, 0);

   CreateButton();
   CreateStatusObjects();

   Print("==================================================");
   Print("AXIOM REVERSAL 90 EA INITIALIZED");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: M1");
   Print("Trigger: ", DoubleToString(InpTrigger, 1), "%");
   Print("Lot size: ", DoubleToString(InpLotSize, 2));
   Print("Maximum positions: ", InpMaxPositions);
   Print("Magic number: ", InpMagicNumber);
   Print("STATUS: STOPPED");
   Print("Press START to activate trading.");
   Print("==================================================");

   UpdateChartStatus();

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================

void OnDeinit(const int reason)
{
   ObjectDelete(0, g_buttonName);
   ObjectDelete(0, g_statusName);
   ObjectDelete(0, g_progressName);

   Print("AXIOM REVERSAL 90 EA DEINITIALIZED.");
}

//==================================================================
// MAIN TICK FUNCTION
//==================================================================

void OnTick()
{
   CheckForNewM1Candle();

   CalculateLivePercentages();

   UpdateChartStatus();

   PrintProgress();

   if(!g_running)
      return;

   ProcessReversal();
}

//==================================================================
// CHART BUTTON EVENT
//==================================================================

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam != g_buttonName)
      return;

   if(g_running)
   {
      g_running = false;

      ObjectSetString(0,
                      g_buttonName,
                      OBJPROP_TEXT,
                      "START");

      Print("AXIOM: STOP pressed.");
      Print("AXIOM: Trading stopped.");
   }
   else
   {
      g_running = true;

      ObjectSetString(0,
                      g_buttonName,
                      OBJPROP_TEXT,
                      "STOP");

      Print("AXIOM: START pressed.");
      Print("AXIOM: Live M1 reversal trading ACTIVATED.");
   }

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_STATE,
                    false);

   ChartRedraw();
}

//==================================================================
// CREATE START/STOP BUTTON
//==================================================================

void CreateButton()
{
   if(ObjectFind(0, g_buttonName) >= 0)
      ObjectDelete(0, g_buttonName);

   ObjectCreate(0,
                g_buttonName,
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_CORNER,
                    CORNER_RIGHT_UPPER);

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_XDISTANCE,
                    20);

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_YDISTANCE,
                    20);

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_XSIZE,
                    120);

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_YSIZE,
                    40);

   ObjectSetString(0,
                   g_buttonName,
                   OBJPROP_TEXT,
                   "START");

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_FONTSIZE,
                    12);

   ObjectSetString(0,
                   g_buttonName,
                   OBJPROP_FONT,
                   "Arial");

   ObjectSetInteger(0,
                    g_buttonName,
                    OBJPROP_SELECTABLE,
                    false);
}

//==================================================================
// CREATE STATUS LABELS
//==================================================================

void CreateStatusObjects()
{
   if(ObjectFind(0, g_statusName) >= 0)
      ObjectDelete(0, g_statusName);

   ObjectCreate(0,
                g_statusName,
                OBJ_LABEL,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    g_statusName,
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    g_statusName,
                    OBJPROP_XDISTANCE,
                    15);

   ObjectSetInteger(0,
                    g_statusName,
                    OBJPROP_YDISTANCE,
                    20);

   ObjectSetInteger(0,
                    g_statusName,
                    OBJPROP_FONTSIZE,
                    11);

   ObjectSetString(0,
                   g_statusName,
                   OBJPROP_FONT,
                   "Arial");

   ObjectSetInteger(0,
                    g_statusName,
                    OBJPROP_SELECTABLE,
                    false);

   if(ObjectFind(0, g_progressName) >= 0)
      ObjectDelete(0, g_progressName);

   ObjectCreate(0,
                g_progressName,
                OBJ_LABEL,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    g_progressName,
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    g_progressName,
                    OBJPROP_XDISTANCE,
                    15);

   ObjectSetInteger(0,
                    g_progressName,
                    OBJPROP_YDISTANCE,
                    70);

   ObjectSetInteger(0,
                    g_progressName,
                    OBJPROP_FONTSIZE,
                    11);

   ObjectSetString(0,
                   g_progressName,
                   OBJPROP_FONT,
                   "Arial");

   ObjectSetInteger(0,
                    g_progressName,
                    OBJPROP_SELECTABLE,
                    false);
}

//==================================================================
// NEW M1 CANDLE CHECK
//==================================================================

void CheckForNewM1Candle()
{
   datetime newBar = iTime(_Symbol, PERIOD_M1, 0);

   if(newBar <= 0)
      return;

   if(newBar != g_currentBar)
   {
      g_currentBar = newBar;

      g_buyPercent  = 50.0;
      g_sellPercent = 50.0;

      Print("--------------------------------------------------");
      Print("NEW M1 CANDLE");
      Print("Previous candle forgotten.");
      Print("Fresh live calculation started.");
      Print("--------------------------------------------------");
   }
}

//==================================================================
// LIVE PERCENTAGE CALCULATION
//==================================================================

void CalculateLivePercentages()
{
   double highPrice = iHigh(_Symbol, PERIOD_M1, 0);
   double lowPrice  = iLow(_Symbol, PERIOD_M1, 0);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(highPrice <= 0.0 || lowPrice <= 0.0)
      return;

   double currentPrice = (bid + ask) / 2.0;

   double range = highPrice - lowPrice;

   if(range <= 0.0)
   {
      g_buyPercent  = 50.0;
      g_sellPercent = 50.0;
      return;
   }

   double buyPercent =
      ((currentPrice - lowPrice) / range) * 100.0;

   if(buyPercent < 0.0)
      buyPercent = 0.0;

   if(buyPercent > 100.0)
      buyPercent = 100.0;

   g_buyPercent = buyPercent;

   g_sellPercent = 100.0 - g_buyPercent;
}//==================================================================
// COUNT EA POSITIONS
//==================================================================

int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);
      long posType  = PositionGetInteger(POSITION_TYPE);

      if(symbol != _Symbol)
         continue;

      if((ulong)magic != InpMagicNumber)
         continue;

      if(posType == (long)type)
         count++;
   }

   return count;
}

//==================================================================
// CLOSE ALL EA POSITIONS OF A SPECIFIC TYPE
//==================================================================

bool ClosePositions(ENUM_POSITION_TYPE type)
{
   bool success = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);
      long posType  = PositionGetInteger(POSITION_TYPE);

      if(symbol != _Symbol)
         continue;

      if((ulong)magic != InpMagicNumber)
         continue;

      if(posType != (long)type)
         continue;

      ResetLastError();

      if(!trade.PositionClose(ticket))
      {
         Print("AXIOM ERROR: Could not close ticket #",
               ticket,
               " | Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());

         success = false;
      }
      else
      {
         Print("AXIOM: Closed ticket #", ticket);
      }
   }

   return success;
}

//==================================================================
// OPEN BUY POSITIONS
//==================================================================

bool OpenBuyPositions()
{
   int existingBuys =
      CountPositions(POSITION_TYPE_BUY);

   int amount =
      InpMaxPositions - existingBuys;

   if(amount <= 0)
      return true;

   bool success = true;

   for(int i = 0; i < amount; i++)
   {
      ResetLastError();

      if(!trade.Buy(InpLotSize,
                    _Symbol,
                    0.0,
                    0.0,
                    0.0,
                    "Axiom BUY"))
      {
         Print("AXIOM ERROR: BUY failed.",
               " Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());

         success = false;
         break;
      }

      Print("AXIOM: BUY opened.",
            " Order=",
            trade.ResultOrder(),
            " | Lot=",
            DoubleToString(InpLotSize, 2));
   }

   if(success)
      g_lastDirection = 1;

   return success;
}

//==================================================================
// OPEN SELL POSITIONS
//==================================================================

bool OpenSellPositions()
{
   int existingSells =
      CountPositions(POSITION_TYPE_SELL);

   int amount =
      InpMaxPositions - existingSells;

   if(amount <= 0)
      return true;

   bool success = true;

   for(int i = 0; i < amount; i++)
   {
      ResetLastError();

      if(!trade.Sell(InpLotSize,
                     _Symbol,
                     0.0,
                     0.0,
                     0.0,
                     "Axiom SELL"))
      {
         Print("AXIOM ERROR: SELL failed.",
               " Retcode=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());

         success = false;
         break;
      }

      Print("AXIOM: SELL opened.",
            " Order=",
            trade.ResultOrder(),
            " | Lot=",
            DoubleToString(InpLotSize, 2));
   }

   if(success)
      g_lastDirection = -1;

   return success;
}

//==================================================================
// GET CURRENT EA DIRECTION
//==================================================================

int GetCurrentDirection()
{
   int buys =
      CountPositions(POSITION_TYPE_BUY);

   int sells =
      CountPositions(POSITION_TYPE_SELL);

   if(buys > 0 && sells == 0)
      return 1;

   if(sells > 0 && buys == 0)
      return -1;

   return 0;
}

//==================================================================
// PROCESS 90% REVERSAL
//==================================================================

void ProcessReversal()
{
   int direction =
      GetCurrentDirection();

   //===============================================================
   // BUY REACHES 90%
   // CLOSE BUY -> OPEN SELL
   //===============================================================

   if(g_buyPercent >= InpTrigger)
   {
      if(direction != -1)
      {
         Print("==================================================");
         Print("AXIOM 90% SIGNAL: BUY = ",
               DoubleToString(g_buyPercent, 1),
               "%");

         Print("AXIOM ACTION: Closing BUY positions...");

         bool closed =
            ClosePositions(POSITION_TYPE_BUY);

         if(closed)
         {
            Print("AXIOM ACTION: BUY positions closed.");
            Print("AXIOM ACTION: Opening SELL immediately.");

            OpenSellPositions();
         }
         else
         {
            Print("AXIOM: BUY closure incomplete.");
            Print("AXIOM: SELL opening cancelled for this tick.");
         }

         Print("==================================================");
      }

      return;
   }

   //===============================================================
   // SELL REACHES 90%
   // CLOSE SELL -> OPEN BUY
   //===============================================================

   if(g_sellPercent >= InpTrigger)
   {
      if(direction != 1)
      {
         Print("==================================================");
         Print("AXIOM 90% SIGNAL: SELL = ",
               DoubleToString(g_sellPercent, 1),
               "%");

         Print("AXIOM ACTION: Closing SELL positions...");

         bool closed =
            ClosePositions(POSITION_TYPE_SELL);

         if(closed)
         {
            Print("AXIOM ACTION: SELL positions closed.");
            Print("AXIOM ACTION: Opening BUY immediately.");

            OpenBuyPositions();
         }
         else
         {
            Print("AXIOM: SELL closure incomplete.");
            Print("AXIOM: BUY opening cancelled for this tick.");
         }

         Print("==================================================");
      }

      return;
   }
}//==================================================================
// EXPERTS PROGRESS
//==================================================================

void PrintProgress()
{
   static datetime lastPrintTime = 0;

   datetime now = TimeCurrent();

   // Print approximately once per second.
   // This prevents the Experts tab from being flooded.
   if(now == lastPrintTime)
      return;

   lastPrintTime = now;

   string state = "STOPPED";

   if(g_running)
      state = "RUNNING";

   int buys =
      CountPositions(POSITION_TYPE_BUY);

   int sells =
      CountPositions(POSITION_TYPE_SELL);

   Print("AXIOM | ",
         state,
         " | M1 BUY=",
         DoubleToString(g_buyPercent, 1),
         "% | SELL=",
         DoubleToString(g_sellPercent, 1),
         "% | BUY POS=",
         buys,
         " | SELL POS=",
         sells);
}

//==================================================================
// UPDATE CHART STATUS
//==================================================================

void UpdateChartStatus()
{
   string state = "STOPPED";

   if(g_running)
      state = "RUNNING";

   string statusText =
      "AXIOM REVERSAL 90 EA\n"
      "Symbol: " + _Symbol + "\n"
      "Timeframe: M1\n"
      "Status: " + state;

   ObjectSetString(0,
                   g_statusName,
                   OBJPROP_TEXT,
                   statusText);

   string progressText =
      "BUY: " +
      DoubleToString(g_buyPercent, 1) +
      "%    |    SELL: " +
      DoubleToString(g_sellPercent, 1) +
      "%\n"
      "Trigger: " +
      DoubleToString(InpTrigger, 1) +
      "%";

   ObjectSetString(0,
                   g_progressName,
                   OBJPROP_TEXT,
                   progressText);
}

//==================================================================
// END OF AXIOM REVERSAL 90 EA
//==================================================================
