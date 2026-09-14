#property strict

input double LotSize = 0.01;
input double ProfitPerTradeUSD = 0.40;
input double StopLossPerTradeUSD = 1.00;
input int MaxHoldMinutes = 60;
input int MaxOpenPositions = 2;
input int EMA_Fast = 9;
input int EMA_Slow = 21;

int emaFastHandle, emaSlowHandle;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_M1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE)
   {
      Print("Failed to create EMA handles");
      return(INIT_FAILED);
   }
   Print("=== TREND $0.40 + HOURLY SL STARTED ===");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   datetime now = TimeCurrent();
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!= _Symbol) continue;
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int minutesOpen = (int)((now - openTime)/60);

      bool hitTP = profit >= ProfitPerTradeUSD;
      bool hitSL = profit <= -StopLossPerTradeUSD;
      bool hitTime = minutesOpen >= MaxHoldMinutes;

      if(hitTP || hitSL || hitTime)
      {
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL;
         req.symbol = _Symbol;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = (ENUM_ORDER_TYPE)(1 - PositionGetInteger(POSITION_TYPE));
         req.position = ticket;
         req.price = (req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         req.deviation = 100;
         
         bool sent = OrderSend(req, res);
         if(sent)
         {
            if(hitTP) Print("TP +$", DoubleToString(profit,2), " closed Ticket ", ticket);
            if(hitSL) Print("SL ", DoubleToString(profit,2), " closed Ticket ", ticket);
            if(hitTime) Print("TIME SL ", minutesOpen, "min ", DoubleToString(profit,2), " closed Ticket ", ticket);
         }
         else
         {
            Print("Close FAILED Ticket ", ticket, " Error ", GetLastError(), " ", res.comment);
         }
      }
   }

   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)== _Symbol) count++;
   }
   if(count >= MaxOpenPositions) return;

   double fast[], slow[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   if(CopyBuffer(emaFastHandle, 0, 0, 2, fast) < 2) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 2, slow) < 2) return;

   double
