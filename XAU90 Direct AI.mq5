//+------------------------------------------------------------------+
//|                    XAU90 Direct AI                               |
//|              XAUUSD M1 Live Direction EA                        |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Inputs
input double Lots           = 0.01;
input double TriggerPercent = 90.0;
input int    SlippagePoints = 20;
input long   MagicNumber    = 26092026;

//--- Bot state
bool BotRunning = false;
int  CurrentDirection = 0;       // 1 = BUY, -1 = SELL, 0 = none

//--- Live strength
double BuyStrength  = 50.0;
double SellStrength = 50.0;

//--- Previous price
double LastBid = 0.0;

//--- Duplicate-action protection
ulong LastActionTime = 0;

//--- Chart objects
string StartButton = "XD_START";
string StopButton  = "XD_STOP";
string StatusLabel = "XD_STATUS";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   CreateInterface();

   DetectExistingDirection();

   LastBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   Print("==========================================");
   Print("XAU90 DIRECT AI INITIALIZED");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: M1");
   Print("Trigger: ", TriggerPercent, "%");
   Print("BUY 90% -> BUY");
   Print("SELL 90% -> SELL");
   Print("Press START to activate.");
   Print("==========================================");

   UpdateDisplay();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, StartButton);
   ObjectDelete(0, StopButton);
   ObjectDelete(0, StatusLabel);

   Print("XAU90 Direct AI deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only M1
   if(Period() != PERIOD_M1)
   {
      UpdateDisplay();
      return;
   }

   //--- Only XAUUSD
   if(StringFind(_Symbol, "XAUUSD") < 0)
   {
      UpdateDisplay();
      return;
   }

   //--- Calculate live strength
   CalculateLiveStrength();

   //--- Update screen
   UpdateDisplay();

   //--- Do nothing while stopped
   if(!BotRunning)
      return;

   //--- Process direct-direction logic
   ProcessDirectLogic();

   //--- Remember current price
   LastBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Calculate live M1 strength                                       |
//+------------------------------------------------------------------+
void CalculateLiveStrength()
{
   double openPrice = iOpen(_Symbol, PERIOD_M1, 0);
   double highPrice = iHigh(_Symbol, PERIOD_M1, 0);
   double lowPrice  = iLow(_Symbol, PERIOD_M1, 0);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(openPrice <= 0 || highPrice <= 0 || lowPrice <= 0)
   {
      BuyStrength  = 50.0;
      SellStrength = 50.0;
      return;
   }

   double range = highPrice - lowPrice;

   //--- Very small candle
   if(range <= (_Point * 2.0))
   {
      if(bid > openPrice)
      {
         BuyStrength  = 60.0;
         SellStrength = 40.0;
      }
      else if(bid < openPrice)
      {
         BuyStrength  = 40.0;
         SellStrength = 60.0;
      }
      else
      {
         BuyStrength  = 50.0;
         SellStrength = 50.0;
      }

      return;
   }

   //--- Live price position inside current candle
   double position = (bid - lowPrice) / range;

   position = MathMax(0.0, MathMin(1.0, position));

   //--- Base percentages
   BuyStrength  = position * 100.0;
   SellStrength = 100.0 - BuyStrength;

   //--- Live tick momentum
   if(LastBid > 0)
   {
      if(bid > LastBid)
      {
         BuyStrength  += 2.0;
         SellStrength -= 2.0;
      }
      else if(bid < LastBid)
      {
         BuyStrength  -= 2.0;
         SellStrength += 2.0;
      }
   }

   //--- Keep values within 0-100
   BuyStrength  = MathMax(0.0, MathMin(100.0, BuyStrength));
   SellStrength = MathMax(0.0, MathMin(100.0, SellStrength));
}

//+------------------------------------------------------------------+
//| Direct trading logic                                             |
//+------------------------------------------------------------------+
void ProcessDirectLogic()
{
   int NewDirection = 0;

   //===============================================================
   // BUY reaches 90% -> BUY
   //===============================================================
   if(BuyStrength >= TriggerPercent)
   {
      NewDirection = 1;
   }

   //===============================================================
   // SELL reaches 90% -> SELL
   //===============================================================
   else if(SellStrength >= TriggerPercent)
   {
      NewDirection = -1;
   }

   //--- No signal
   if(NewDirection == 0)
      return;

   //--- Already trading in that direction
   if(NewDirection == CurrentDirection)
      return;

   //--- Prevent duplicate rapid execution
   ulong now = GetTickCount64();

   if(LastActionTime > 0)
   {
      if((now - LastActionTime) < 300)
         return;
   }

   //--- Change direction
   ChangeDirection(NewDirection);

   LastActionTime = now;
}

//+------------------------------------------------------------------+
//| Change trading direction                                         |
//+------------------------------------------------------------------+
void ChangeDirection(int direction)
{
   Print("==========================================");
   Print("90% LIVE SIGNAL DETECTED");

   Print("BUY STRENGTH  = ",
         DoubleToString(BuyStrength, 1), "%");

   Print("SELL STRENGTH = ",
         DoubleToString(SellStrength, 1), "%");

   //--- Close previous EA positions
   CloseOurPositions();

   //--- Open the same direction as the signal
   if(direction == 1)
   {
      Print("ACTION: BUY 90% -> OPEN BUY");
      OpenBuy();
   }
   else
   {
      Print("ACTION: SELL 90% -> OPEN SELL");
      OpenSell();
   }

   CurrentDirection = direction;

   Print("==========================================");
}

//+------------------------------------------------------------------+
//| Close EA positions                                               |
//+------------------------------------------------------------------+
void CloseOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(trade.PositionClose(ticket))
      {
         Print("Closed position #", ticket);
      }
      else
      {
         Print("FAILED closing #",
               ticket,
               " | ",
               trade.ResultRetcodeDescription());
      }
   }
}//+------------------------------------------------------------------+
//| Open BUY                                                         |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ask <= 0)
   {
      Print("BUY blocked: invalid ASK.");
      return;
   }

   if(trade.Buy(Lots,
                _Symbol,
                0.0,
                0.0,
                0.0,
                "XAU90 DIRECT BUY"))
   {
      Print("BUY OPENED successfully.");
      Print("Lot: ", DoubleToString(Lots, 2));
   }
   else
   {
      Print("BUY FAILED.");
      Print("Retcode: ",
            trade.ResultRetcode(),
            " | ",
            trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Open SELL                                                        |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bid <= 0)
   {
      Print("SELL blocked: invalid BID.");
      return;
   }

   if(trade.Sell(Lots,
                 _Symbol,
                 0.0,
                 0.0,
                 0.0,
                 "XAU90 DIRECT SELL"))
   {
      Print("SELL OPENED successfully.");
      Print("Lot: ", DoubleToString(Lots, 2));
   }
   else
   {
      Print("SELL FAILED.");
      Print("Retcode: ",
            trade.ResultRetcode(),
            " | ",
            trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Detect existing EA direction                                    |
//+------------------------------------------------------------------+
void DetectExistingDirection()
{
   int buyCount  = 0;
   int sellCount = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
         buyCount++;

      if(type == POSITION_TYPE_SELL)
         sellCount++;
   }

   if(buyCount > sellCount && buyCount > 0)
   {
      CurrentDirection = 1;
      Print("Existing direction: BUY");
   }
   else if(sellCount > buyCount && sellCount > 0)
   {
      CurrentDirection = -1;
      Print("Existing direction: SELL");
   }
   else
   {
      CurrentDirection = 0;
      Print("No existing EA position.");
   }
}

//+------------------------------------------------------------------+
//| Create buttons and display                                       |
//+------------------------------------------------------------------+
void CreateInterface()
{
   //--- START
   if(ObjectFind(0, StartButton) < 0)
      ObjectCreate(0, StartButton, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, StartButton, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, StartButton, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, StartButton, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, StartButton, OBJPROP_XSIZE, 100);
   ObjectSetInteger(0, StartButton, OBJPROP_YSIZE, 30);
   ObjectSetString(0, StartButton, OBJPROP_TEXT, "START");

   //--- STOP
   if(ObjectFind(0, StopButton) < 0)
      ObjectCreate(0, StopButton, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, StopButton, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, StopButton, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, StopButton, OBJPROP_YDISTANCE, 70);
   ObjectSetInteger(0, StopButton, OBJPROP_XSIZE, 100);
   ObjectSetInteger(0, StopButton, OBJPROP_YSIZE, 30);
   ObjectSetString(0, StopButton, OBJPROP_TEXT, "STOP");

   //--- STATUS
   if(ObjectFind(0, StatusLabel) < 0)
      ObjectCreate(0, StatusLabel, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, StatusLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, StatusLabel, OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(0, StatusLabel, OBJPROP_YDISTANCE, 25);
   ObjectSetInteger(0, StatusLabel, OBJPROP_FONTSIZE, 11);
}

//+------------------------------------------------------------------+
//| Update display                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   string status = "STOPPED";

   if(BotRunning)
      status = "RUNNING";

   string direction = "NONE";

   if(CurrentDirection == 1)
      direction = "BUY";

   if(CurrentDirection == -1)
      direction = "SELL";

   int positions = CountOurPositions();

   string text =
      "XAU90 DIRECT AI\n"
      "Status: " + status + "\n"
      "Symbol: " + _Symbol + "\n"
      "Timeframe: M1\n"
      "BUY: " + DoubleToString(BuyStrength, 1) + "%\n"
      "SELL: " + DoubleToString(SellStrength, 1) + "%\n"
      "Trigger: " + DoubleToString(TriggerPercent, 1) + "%\n"
      "Direction: " + direction + "\n"
      "Positions: " + IntegerToString(positions);

   ObjectSetString(0,
                   StatusLabel,
                   OBJPROP_TEXT,
                   text);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Count EA positions                                               |
//+------------------------------------------------------------------+
int CountOurPositions()
{
   int count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

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
}//+------------------------------------------------------------------+
//| Chart button events                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   //===============================================================
   // START
   //===============================================================
   if(sparam == StartButton)
   {
      BotRunning = true;

      Print("==========================================");
      Print("XAU90 DIRECT AI: STARTED");
      Print("LIVE M1 SCANNER: ACTIVE");
      Print("BUY 90% -> BUY");
      Print("SELL 90% -> SELL");
      Print("==========================================");

      UpdateDisplay();
   }

   //===============================================================
   // STOP
   //===============================================================
   if(sparam == StopButton)
   {
      BotRunning = false;

      Print("==========================================");
      Print("XAU90 DIRECT AI: MANUALLY STOPPED");
      Print("No new trades will be opened.");
      Print("Existing position remains open.");
      Print("==========================================");

      UpdateDisplay();
   }
}

//+------------------------------------------------------------------+
//| Trade transaction                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   DetectExistingDirection();
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| End of XAU90 Direct AI                                           |
//+------------------------------------------------------------------+
