#property strict
input double LotSize = 0.01;
input double ProfitPerTradeUSD = 0.40;
input double StopLossPerTradeUSD = 1.00; // NEW: max loss per trade
input int MaxHoldMinutes = 60; // NEW: close if open > 60 mins
input int MaxOpenPositions = 2;
input int EMA_Fast = 9;
input int EMA_Slow = 21;

int emaFastHandle, emaSlowHandle;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_M1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   Print("=== TREND $0.40 + HOURLY SL STARTED ===");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   datetime now = TimeCurrent();
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(PositionGetSymbol(i)!= _Symbol) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int minutesOpen = (int)((now - openTime)/60);

      bool hitTP = profit >= ProfitPerTradeUSD;
      bool hitSL = profit <= -StopLossPerTradeUSD;
      bool hitTime = minutesOpen >= MaxHoldMinutes;

      if(hitTP || hitSL || hitTime)
      {
         ulong ticket = PositionGetTicket(i);
         MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL;
         req.symbol = _Symbol;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = (ENUM_ORDER_TYPE)(1 - PositionGetInteger(POSITION_TYPE));
         req.position = ticket;
         req.price = (req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         req.deviation = 100;
         if(OrderSend(req, res))
         {
            if(hitTP) Print("TP +$", profit, " closed");
            if(hitSL) Print("SL -$", profit, " closed");
            if(hitTime) Print("TIME SL ", minutesOpen, "min +$", profit, " closed");
         }
      }
   }

   int count = 0;
   for(int i=0; i<PositionsTotal(); i++) if(PositionGetSymbol(i)==_Symbol) count++;
   if(count >= MaxOpenPositions) return;

   double fast[], slow[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   CopyBuffer(emaFastHandle, 0, 0, 2, fast);
   CopyBuffer(emaSlowHandle, 0, 0, 2, slow);

   double openM1 = iOpen(_Symbol, PERIOD_M1, 0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool upTrend = fast[0] > slow[0];
   bool downTrend = fast[0] < slow[0];

   if(upTrend && bid > openM1) Open(ORDER_TYPE_BUY);
   if(downTrend && bid < openM1) Open(ORDER_TYPE_SELL);
}

void Open(ENUM_ORDER_TYPE type)
{
   double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize;
   req.type=type; req.price=price; req.deviation=100;
   OrderSend(req, res);
}
