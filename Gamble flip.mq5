#property strict
#property version "1.10"

input double LotSize = 0.01;
input double ProfitPerTradeUSD = 0.40;
input double StopLossPerTradeUSD = 1.00;
input int MaxHoldMinutes = 60;
input int MaxOpenPositions = 2;
input int EMA_Fast = 9;
input int EMA_Slow = 21;

int emaFastHandle, emaSlowHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_M1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   Print("=== TREND $0.40 + HOURLY SL v1.10 ===");
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   //--- Close logic
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym!= _Symbol) continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int minutesOpen = (int)((now - openTime)/60);

      if(profit >= ProfitPerTradeUSD || profit <= -StopLossPerTradeUSD || minutesOpen >= MaxHoldMinutes)
      {
         ClosePosition(ticket);
      }
   }

   int count=0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol) count++;
   }
   if(count >= MaxOpenPositions) return;

   double fast[2], slow[2];
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true);
   if(CopyBuffer(emaFastHandle,0,0,2,fast)<2) return;
   if(CopyBuffer(emaSlowHandle,0,0,2,slow)<2) return;

   double openM1 = iOpen(_Symbol,PERIOD_M1,0);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(openM1==0 || bid==0) return;

   if(fast[0] > slow[0] && bid > openM1) DoOpen(ORDER_TYPE_BUY);
   if(fast[0] < slow[0] && bid < openM1) DoOpen(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = PositionGetString(POSITION_SYMBOL);
   req.volume = PositionGetDouble(POSITION_VOLUME);
   req.type = (ENUM_ORDER_TYPE)(1 - PositionGetInteger(POSITION_TYPE));
   req.position = ticket;
   req.price = (req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(req.symbol,SYMBOL_ASK) : SymbolInfoDouble(req.symbol,SYMBOL_BID);
   req.deviation = 100;

   bool ok = OrderSend(req,res);
   if(ok) Print("Closed Ticket ",ticket," Profit ",PositionGetDouble(POSITION_PROFIT));
   else Print("Close FAIL Ticket ",ticket," Err ",GetLastError()," ",res.comment);
   return ok;
}
//+------------------------------------------------------------------+
bool DoOpen(ENUM_ORDER_TYPE type)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = LotSize;
   req.type = type;
   req.price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.deviation = 100;

   bool ok = OrderSend(req,res);
   if(ok) Print("Opened ",EnumToString(type)," Ticket ",res.order);
   else Print("Open FAIL Err ",GetLastError()," ",res.comment);
   return ok;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
}
