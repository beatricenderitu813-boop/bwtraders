//+------------------------------------------------------------------+
//|              XAU90 Direct Profit Cycle                           |
//|              XAUUSD M1 Live Scanner                              |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//--- Inputs
input double Lots                  = 0.01;
input int    PositionsPerSignal   = 3;
input double TriggerPercent       = 90.0;
input double IndividualProfitTarget = 0.35;
input ulong  MagicNumber          = 26092026;
input int    SlippagePoints       = 20;

//--- Runtime
bool   BotRunning = false;
double BuyStrength = 0.0;
double SellStrength = 0.0;

int CurrentSignal = 0;
double LastBid = 0.0;

//--- Button names
string StartButton = "X90_START";
string StopButton  = "X90_STOP";
string StatusLabel = "X90_STATUS";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   CreateInterface();

   LastBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   Print("XAU90 Direct Profit Cycle initialized.");
   Print("Waiting for START.");

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
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(StringFind(_Symbol, "XAUUSD") < 0)
      return;

   CalculateLiveStrength();

   UpdateInterface();

   if(!BotRunning)
      return;

   // First manage positions that have reached
   // their individual profit target.
   ManageIndividualProfits();

   // Then look for a fresh 90% confirmation
   // to fill any missing trade slot.
   ProcessFreshConfirmation();
}

//+------------------------------------------------------------------+
//| Calculate live M1 strength                                       |
//+------------------------------------------------------------------+
void CalculateLiveStrength()
{
   double openPrice = iOpen(_Symbol, PERIOD_M1, 0);
   double highPrice = iHigh(_Symbol, PERIOD_M1, 0);
   double lowPrice  = iLow(_Symbol, PERIOD_M1, 0);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(openPrice <= 0 || highPrice <= 0 || lowPrice <= 0)
      return;

   double range = highPrice - lowPrice;

   if(range <= (_Point * 2.0))
   {
      if(bid >= openPrice)
      {
         BuyStrength = 60.0;
         SellStrength = 40.0;
      }
      else
      {
         BuyStrength = 40.0;
         SellStrength = 60.0;
      }
   }
   else
   {
      double position = (bid - lowPrice) / range;

      BuyStrength = position * 100.0;
      SellStrength = 100.0 - BuyStrength;
   }

   //--- Add live tick momentum
   if(LastBid > 0)
   {
      if(bid > LastBid)
      {
         BuyStrength += 2.0;
         SellStrength -= 2.0;
      }
      else if(bid < LastBid)
      {
         BuyStrength -= 2.0;
         SellStrength += 2.0;
      }
   }

   //--- Keep values between 0 and 100
   BuyStrength = MathMax(0.0, MathMin(100.0, BuyStrength));
   SellStrength = MathMax(0.0, MathMin(100.0, SellStrength));

   LastBid = bid;
}

//+------------------------------------------------------------------+
//| Determine current 90% confirmation                               |
//|  1 = BUY                                                         |
//| -1 = SELL                                                        |
//|  0 = no confirmation                                             |
//+------------------------------------------------------------------+
int GetConfirmedDirection()
{
   if(BuyStrength >= TriggerPercent)
      return 1;

   if(SellStrength >= TriggerPercent)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Process fresh confirmation                                       |
//+------------------------------------------------------------------+
void ProcessFreshConfirmation()
{
   int signal = GetConfirmedDirection();

   if(signal == 0)
      return;

   int existingCount = CountPositions();

   // If there are no EA positions, use the 90% confirmation
   // to start the first group of 3.
   if(existingCount == 0)
   {
      CurrentSignal = signal;

      Print("90% CONFIRMATION detected: ",
            DirectionText(signal),
            " | Opening ",
            PositionsPerSignal,
            " positions.");

      OpenPositions(signal, PositionsPerSignal);

      return;
   }

   // If there is a missing slot after a profitable position
   // was closed, fill it ONLY when a new 90% confirmation exists.
   int missing = PositionsPerSignal - existingCount;

   if(missing > 0)
   {
      Print("Fresh 90% confirmation: ",
            DirectionText(signal),
            " | Missing slots: ",
            missing,
            " | Opening replacement.");

      CurrentSignal = signal;

      OpenPositions(signal, missing);
   }
}

//+------------------------------------------------------------------+
//| Manage each individual position                                  |
//+------------------------------------------------------------------+
void ManageIndividualProfits()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol)
         continue;

      if((ulong)magic != MagicNumber)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT);

      // Individual position target
      if(profit >= IndividualProfitTarget)
      {
         Print("Profit target reached on ticket ",
               ticket,
               " | Profit = ",
               DoubleToString(profit, 2),
               " | Closing position.");

         bool closed = trade.PositionClose(ticket);

         if(closed)
         {
            Print("Ticket ",
                  ticket,
                  " closed at individual profit target.");

            // IMPORTANT:
            // We DO NOT immediately replace it here.
            // The next tick must contain a valid 90%
            // BUY or SELL confirmation.
         }
         else
         {
            Print("Failed to close ticket ",
                  ticket,
                  " | Retcode = ",
                  trade.ResultRetcode(),
                  " | ",
                  trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open positions                                                   |
//+------------------------------------------------------------------+
void OpenPositions(int direction, int numberToOpen)
{
   if(numberToOpen <= 0)
      return;

   for(int i = 0; i < numberToOpen; i++)
   {
      bool result = false;

      if(direction == 1)
      {
         result = trade.Buy(
            Lots,
            _Symbol,
            0.0,
            0.0,
            0.0,
            "XAU90 BUY"
         );
      }
      else if(direction == -1)
      {
         result = trade.Sell(
            Lots,
            _Symbol,
            0.0,
            0.0,
            0.0,
            "XAU90 SELL"
         );
      }

      if(result)
      {
         Print("Opened ",
               DirectionText(direction),
               " position #",
               i + 1,
               " of ",
               numberToOpen,
               ".");
      }
      else
      {
         Print("FAILED to open ",
               DirectionText(direction),
               " position #",
               i + 1,
               " | Retcode = ",
               trade.ResultRetcode(),
               " | ",
               trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Count this EA's positions                                        |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Direction text                                                   |
//+------------------------------------------------------------------+
string DirectionText(int direction)
{
   if(direction == 1)
      return "BUY";

   if(direction == -1)
      return "SELL";

   return "NONE";
}//+------------------------------------------------------------------+
//| Create chart interface                                           |
//+------------------------------------------------------------------+
void CreateInterface()
{
   //--- START button
   ObjectCreate(0, StartButton, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, StartButton, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, StartButton, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, StartButton, OBJPROP_XSIZE, 100);
   ObjectSetInteger(0, StartButton, OBJPROP_YSIZE, 35);

   ObjectSetString(0, StartButton, OBJPROP_TEXT, "START");

   ObjectSetInteger(0, StartButton, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- STOP button
   ObjectCreate(0, StopButton, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, StopButton, OBJPROP_XDISTANCE, 130);
   ObjectSetInteger(0, StopButton, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, StopButton, OBJPROP_XSIZE, 100);
   ObjectSetInteger(0, StopButton, OBJPROP_YSIZE, 35);

   ObjectSetString(0, StopButton, OBJPROP_TEXT, "STOP");

   ObjectSetInteger(0, StopButton, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Status label
   ObjectCreate(0, StatusLabel, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, StatusLabel, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, StatusLabel, OBJPROP_YDISTANCE, 80);

   ObjectSetInteger(0, StatusLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ObjectSetInteger(0, StatusLabel, OBJPROP_FONTSIZE, 11);

   ObjectSetString(0, StatusLabel, OBJPROP_FONT, "Arial");

   ObjectSetString(
      0,
      StatusLabel,
      OBJPROP_TEXT,
      "XAU90 DIRECT AI\nWaiting for START..."
   );

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update scanner display                                           |
//+------------------------------------------------------------------+
void UpdateInterface()
{
   int count = CountPositions();

   string status;

   if(BotRunning)
      status = "RUNNING";
   else
      status = "STOPPED";

   string confirmation = "NONE";

   int signal = GetConfirmedDirection();

   if(signal == 1)
      confirmation = "BUY 90%+";
   else if(signal == -1)
      confirmation = "SELL 90%+";

   string text =
      "XAU90 DIRECT PROFIT CYCLE\n"
      "Status: " + status + "\n"
      "BUY: " + DoubleToString(BuyStrength, 1) + "%\n"
      "SELL: " + DoubleToString(SellStrength, 1) + "%\n"
      "Confirmation: " + confirmation + "\n"
      "Open Positions: " + IntegerToString(count) + "\n"
      "Target Each: " + DoubleToString(IndividualProfitTarget, 2) + "\n"
      "Positions Group: " + IntegerToString(PositionsPerSignal);

   ObjectSetString(
      0,
      StatusLabel,
      OBJPROP_TEXT,
      text
   );

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Chart events                                                     |
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

   //--- START
   if(sparam == StartButton)
   {
      BotRunning = true;

      Print("================================================");
      Print("XAU90 BOT STARTED");
      Print("Live M1 scanning is ACTIVE.");
      Print("Waiting for 90% confirmation.");
      Print("================================================");

      UpdateInterface();
   }

   //--- STOP
   if(sparam == StopButton)
   {
      BotRunning = false;

      Print("================================================");
      Print("XAU90 BOT STOPPED");
      Print("Existing positions remain open.");
      Print("No new trades will be opened.");
      Print("================================================");

      UpdateInterface();
   }
}//+------------------------------------------------------------------+
//| Extra safety check                                               |
//+------------------------------------------------------------------+
bool IsOurPosition(ulong ticket)
{
   if(ticket == 0)
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get individual position profit                                   |
//+------------------------------------------------------------------+
double GetPositionProfit(ulong ticket)
{
   if(!IsOurPosition(ticket))
      return 0.0;

   return PositionGetDouble(POSITION_PROFIT);
}

//+------------------------------------------------------------------+
//| Current EA position count by direction                           |
//+------------------------------------------------------------------+
int CountDirection(int direction)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(direction == 1 && type == POSITION_TYPE_BUY)
         count++;

      if(direction == -1 && type == POSITION_TYPE_SELL)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Expert tick statistics                                           |
//+------------------------------------------------------------------+
void PrintScannerStatus()
{
   static datetime lastPrint = 0;

   datetime now = TimeCurrent();

   // Print approximately once every 10 seconds
   // so the Experts tab remains readable.
   if(now - lastPrint < 10)
      return;

   lastPrint = now;

   int signal = GetConfirmedDirection();

   Print(
      "M1 SCANNER | BUY=",
      DoubleToString(BuyStrength, 1),
      "% | SELL=",
      DoubleToString(SellStrength, 1),
      "% | Confirmation=",
      DirectionText(signal),
      " | Positions=",
      CountPositions()
   );
}

//+------------------------------------------------------------------+
//| Final tick monitor                                               |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(BotRunning)
      PrintScannerStatus();
}
