//+------------------------------------------------------------------+
//|                 AXIOM REVERSAL 90 AI SCANNER                    |
//|                         M1 LIVE EA                               |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Axiom live M1 90-percent reversal scanner"

#include <Trade/Trade.mqh>

CTrade trade;

//============================== INPUTS =============================

input double InpLotSize      = 0.01;
input int    InpMaxPositions = 10;
input double InpTrigger      = 90.0;
input long   InpMagicNumber  = 26092026;
input int    InpDeviation    = 20;

//============================== GLOBALS ============================

bool     g_running       = false;
datetime g_currentCandle = 0;

double   g_buyPercent  = 50.0;
double   g_sellPercent = 50.0;

string BUTTON_NAME = "AXIOM_START_STOP";
string STATUS_NAME = "AXIOM_STATUS";
string BUY_NAME    = "AXIOM_BUY";
string SELL_NAME   = "AXIOM_SELL";
string INFO_NAME   = "AXIOM_INFO";

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);

   g_currentCandle = iTime(_Symbol, PERIOD_M1, 0);

   CreateButton();
   CreateStatusObjects();

   Print("================================================");
   Print("AXIOM REVERSAL 90 AI SCANNER");
   Print("INITIALIZED");
   Print("SYMBOL: ", _Symbol);
   Print("TIMEFRAME: M1");
   Print("TRIGGER: ", DoubleToString(InpTrigger, 1), "%");
   Print("MODE: LIVE M1 SCANNING");
   Print("================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, BUTTON_NAME);
   ObjectDelete(0, STATUS_NAME);
   ObjectDelete(0, BUY_NAME);
   ObjectDelete(0, SELL_NAME);
   ObjectDelete(0, INFO_NAME);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckForNewM1Candle();

   // Scan current forming candle continuously
   CalculateAIScanner();

   UpdateChartStatus();

   PrintProgress();

   if(!g_running)
      return;

   ProcessReversal();
}

//+------------------------------------------------------------------+
//| CHART EVENTS                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // START / STOP
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BUTTON_NAME)
      {
         g_running = !g_running;

         if(g_running)
         {
            ObjectSetString(0,
                            BUTTON_NAME,
                            OBJPROP_TEXT,
                            "STOP");

            Print("AXIOM SCANNER STARTED");
         }
         else
         {
            ObjectSetString(0,
                            BUTTON_NAME,
                            OBJPROP_TEXT,
                            "START");

            Print("AXIOM SCANNER STOPPED");
         }

         ChartRedraw();
      }
   }

   // Re-center button when chart changes size
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      CenterButton();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| CREATE BUTTON                                                    |
//+------------------------------------------------------------------+
void CreateButton()
{
   if(ObjectFind(0, BUTTON_NAME) >= 0)
      ObjectDelete(0, BUTTON_NAME);

   ObjectCreate(0,
                BUTTON_NAME,
                OBJ_BUTTON,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_XSIZE,
                    150);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_YSIZE,
                    45);

   ObjectSetString(0,
                   BUTTON_NAME,
                   OBJPROP_TEXT,
                   "START");

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_FONTSIZE,
                    12);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_SELECTABLE,
                    false);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_SELECTED,
                    false);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_HIDDEN,
                    false);

   CenterButton();
}

//+------------------------------------------------------------------+
//| CENTER BUTTON                                                    |
//+------------------------------------------------------------------+
void CenterButton()
{
   long chartWidth =
      ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);

   long chartHeight =
      ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int buttonWidth  = 150;
   int buttonHeight = 45;

   int x =
      (int)((chartWidth - buttonWidth) / 2);

   int y =
      (int)((chartHeight - buttonHeight) / 2);

   if(x < 0)
      x = 0;

   if(y < 0)
      y = 0;

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_XDISTANCE,
                    x);

   ObjectSetInteger(0,
                    BUTTON_NAME,
                    OBJPROP_YDISTANCE,
                    y);
}

//+------------------------------------------------------------------+
//| CREATE STATUS OBJECTS                                            |
//+------------------------------------------------------------------+
void CreateStatusObjects()
{
   CreateLabel(STATUS_NAME, 15, 20, 12);
   CreateLabel(BUY_NAME,    15, 50, 11);
   CreateLabel(SELL_NAME,   15, 75, 11);
   CreateLabel(INFO_NAME,   15, 105, 10);
}

//+------------------------------------------------------------------+
//| CREATE LABEL                                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name,
                 int x,
                 int y,
                 int fontSize)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0,
                name,
                OBJ_LABEL,
                0,
                0,
                0);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_XDISTANCE,
                    x);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_YDISTANCE,
                    y);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_FONTSIZE,
                    fontSize);

   ObjectSetString(0,
                   name,
                   OBJPROP_FONT,
                   "Arial");

   ObjectSetInteger(0,
                    name,
                    OBJPROP_SELECTABLE,
                    false);
}

//+------------------------------------------------------------------+
//| NEW M1 CANDLE                                                    |
//+------------------------------------------------------------------+
void CheckForNewM1Candle()
{
   datetime newCandle =
      iTime(_Symbol, PERIOD_M1, 0);

   if(newCandle <= 0)
      return;

   if(newCandle != g_currentCandle)
   {
      g_currentCandle = newCandle;

      // Forget previous candle
      g_buyPercent  = 50.0;
      g_sellPercent = 50.0;

      Print("NEW M1 CANDLE");
      Print("SCANNER RESET FOR CURRENT CANDLE");
   }
}

//+------------------------------------------------------------------+
//| LIVE AI-STYLE SCANNER                                            |
//+------------------------------------------------------------------+
void CalculateAIScanner()
{
   double open =
      iOpen(_Symbol, PERIOD_M1, 0);

   double high =
      iHigh(_Symbol, PERIOD_M1, 0);

   double low =
      iLow(_Symbol, PERIOD_M1, 0);

   double bid =
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(open <= 0 ||
      high <= 0 ||
      low <= 0 ||
      bid <= 0)
      return;

   double range = high - low;

   if(range <= 0)
   {
      g_buyPercent  = 50.0;
      g_sellPercent = 50.0;
      return;
   }

   //===============================================================
   // CURRENT PRICE POSITION
   //===============================================================

   double locationScore =
      ((bid - low) / range) * 100.0;

   //===============================================================
   // CURRENT CANDLE BODY
   //===============================================================

   double body =
      bid - open;

   double bodyScore =
      50.0 + (body / range) * 50.0;

   if(bodyScore > 100.0)
      bodyScore = 100.0;

   if(bodyScore < 0.0)
      bodyScore = 0.0;

   //===============================================================
   // LIVE TICK MOMENTUM
   //===============================================================

   static double previousBid = 0.0;

   double momentumScore = 50.0;

   if(previousBid > 0)
   {
      if(bid > previousBid)
         momentumScore = 75.0;

      else if(bid < previousBid)
         momentumScore = 25.0;
   }

   previousBid = bid;

   //===============================================================
   // SHORT-TERM DIRECTION
   //===============================================================

   double shortTermScore = 50.0;

   if(bid > open)
      shortTermScore = 70.0;

   else if(bid < open)
      shortTermScore = 30.0;

   //===============================================================
   // WEIGHTED SCANNER
   //===============================================================

   double buyScore =
      (locationScore  * 0.35) +
      (bodyScore      * 0.30) +
      (momentumScore  * 0.20) +
      (shortTermScore * 0.15);

   if(buyScore > 100.0)
      buyScore = 100.0;

   if(buyScore < 0.0)
      buyScore = 0.0;

   g_buyPercent = buyScore;

   // BUY + SELL = 100%
   g_sellPercent = 100.0 - g_buyPercent;

   if(g_sellPercent > 100.0)
      g_sellPercent = 100.0;

   if(g_sellPercent < 0.0)
      g_sellPercent = 0.0;
}//+------------------------------------------------------------------+
//| COUNT POSITIONS OF ONE TYPE                                      |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
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

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      ENUM_POSITION_TYPE positionType =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);

      if(symbol == _Symbol &&
         magic == InpMagicNumber &&
         positionType == type)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| COUNT ALL AXIOM POSITIONS                                        |
//+------------------------------------------------------------------+
int CountAllPositions()
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

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol &&
         magic == InpMagicNumber)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS OF TYPE                                      |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

      ENUM_POSITION_TYPE positionType =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);

      if(symbol != _Symbol)
         continue;

      if(magic != InpMagicNumber)
         continue;

      if(positionType != type)
         continue;

      ResetLastError();

      if(trade.PositionClose(ticket))
      {
         Print("AXIOM CLOSED POSITION | TICKET=",
               ticket);
      }
      else
      {
         Print("AXIOM CLOSE FAILED | TICKET=",
               ticket,
               " | RETCODE=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN BUY POSITIONS                                               |
//+------------------------------------------------------------------+
void OpenBuyPositions()
{
   int current =
      CountPositions(POSITION_TYPE_BUY);

   int available =
      InpMaxPositions - current;

   if(available <= 0)
   {
      Print("BUY MAX POSITIONS REACHED");
      return;
   }

   for(int i = 0; i < available; i++)
   {
      ResetLastError();

      if(trade.Buy(InpLotSize,
                   _Symbol,
                   0.0,
                   0.0,
                   0.0,
                   "AXIOM BUY"))
      {
         Print("AXIOM BUY OPENED | LOT=",
               DoubleToString(InpLotSize, 2));
      }
      else
      {
         Print("AXIOM BUY FAILED | RETCODE=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());

         break;
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN SELL POSITIONS                                              |
//+------------------------------------------------------------------+
void OpenSellPositions()
{
   int current =
      CountPositions(POSITION_TYPE_SELL);

   int available =
      InpMaxPositions - current;

   if(available <= 0)
   {
      Print("SELL MAX POSITIONS REACHED");
      return;
   }

   for(int i = 0; i < available; i++)
   {
      ResetLastError();

      if(trade.Sell(InpLotSize,
                    _Symbol,
                    0.0,
                    0.0,
                    0.0,
                    "AXIOM SELL"))
      {
         Print("AXIOM SELL OPENED | LOT=",
               DoubleToString(InpLotSize, 2));
      }
      else
      {
         Print("AXIOM SELL FAILED | RETCODE=",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());

         break;
      }
   }
}

//+------------------------------------------------------------------+
//| GET CURRENT POSITION DIRECTION                                   |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| EXACT 90% REVERSAL ENGINE                                        |
//+------------------------------------------------------------------+
void ProcessReversal()
{
   int direction =
      GetCurrentDirection();

   //===============================================================
   // BUY 90% MEANS OPEN SELL
   //===============================================================

   if(g_buyPercent >= InpTrigger)
   {
      // Already SELL: keep holding it.
      if(direction == -1)
         return;

      // BUY positions exist:
      // close BUY first, then immediately SELL.
      if(direction == 1)
      {
         Print("========================================");
         Print("BUY REACHED 90%");
         Print("ACTION: CLOSE BUY -> OPEN SELL");
         Print("========================================");

         ClosePositions(POSITION_TYPE_BUY);

         // Immediate opposite entry
         OpenSellPositions();

         return;
      }

      // No positions:
      // BUY 90 means OPEN SELL.
      if(direction == 0)
      {
         Print("========================================");
         Print("BUY REACHED 90%");
         Print("ACTION: OPEN SELL");
         Print("========================================");

         OpenSellPositions();

         return;
      }
   }

   //===============================================================
   // SELL 90% MEANS OPEN BUY
   //===============================================================

   if(g_sellPercent >= InpTrigger)
   {
      // Already BUY: keep holding it.
      if(direction == 1)
         return;

      // SELL positions exist:
      // close SELL first, then immediately BUY.
      if(direction == -1)
      {
         Print("========================================");
         Print("SELL REACHED 90%");
         Print("ACTION: CLOSE SELL -> OPEN BUY");
         Print("========================================");

         ClosePositions(POSITION_TYPE_SELL);

         // Immediate opposite entry
         OpenBuyPositions();

         return;
      }

      // No positions:
      // SELL 90 means OPEN BUY.
      if(direction == 0)
      {
         Print("========================================");
         Print("SELL REACHED 90%");
         Print("ACTION: OPEN BUY");
         Print("========================================");

         OpenBuyPositions();

         return;
      }
   }
}

//+------------------------------------------------------------------+
//| SCANNER DIRECTION                                                |
//+------------------------------------------------------------------+
string ScannerDirection()
{
   if(g_buyPercent >= g_sellPercent)
      return "BUY";

   return "SELL";
}//+------------------------------------------------------------------+
//| PRINT PROGRESS                                                   |
//+------------------------------------------------------------------+
void PrintProgress()
{
   static datetime lastPrint = 0;

   datetime now =
      TimeCurrent();

   // One progress message per second
   if(now == lastPrint)
      return;

   lastPrint = now;

   string direction =
      ScannerDirection();

   Print("AXIOM AI SCANNER | ",
         "M1 LIVE | ",
         "BUY=",
         DoubleToString(g_buyPercent, 1),
         "% | ",
         "SELL=",
         DoubleToString(g_sellPercent, 1),
         "% | ",
         "SCANNER=",
         direction,
         " | ",
         "STATUS=",
         (g_running ? "RUNNING" : "STOPPED"),
         " | ",
         "POSITIONS=",
         CountAllPositions());
}

//+------------------------------------------------------------------+
//| UPDATE CHART STATUS                                              |
//+------------------------------------------------------------------+
void UpdateChartStatus()
{
   string direction =
      ScannerDirection();

   string status;

   if(!g_running)
      status = "STOPPED - PRESS START";

   else
      status = "AI SCANNER ACTIVE - LIVE M1";

   ObjectSetString(0,
                   STATUS_NAME,
                   OBJPROP_TEXT,
                   status);

   ObjectSetString(0,
                   BUY_NAME,
                   OBJPROP_TEXT,
                   "BUY STRENGTH: " +
                   DoubleToString(g_buyPercent, 1) +
                   "%");

   ObjectSetString(0,
                   SELL_NAME,
                   OBJPROP_TEXT,
                   "SELL STRENGTH: " +
                   DoubleToString(g_sellPercent, 1) +
                   "%");

   ObjectSetString(0,
                   INFO_NAME,
                   OBJPROP_TEXT,
                   "SCANNER: " +
                   direction +
                   " | TRIGGER: " +
                   DoubleToString(InpTrigger, 1) +
                   "% | M1 LIVE | POSITIONS: " +
                   IntegerToString(CountAllPositions()));

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
