#property strict
input double FixedLot = 0.10; // 0.10 lot = $1 per $1 move, high risk for $10
input int TakeProfitPoints = 300; // 30 pips = ~ $3 profit per win
input int StopLossPoints = 200;   // 20 pips = ~ $2 loss per loss
input int EMA_Fast = 3;
input int EMA_Slow = 6;

int emaFastHandle, emaSlowHandle;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, _Period, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, _Period, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   Print("=== GAMBLE MODE ON ", _Symbol, " Lot ", FixedLot, " ===");
   Print("WARNING: This will blow $10 fast if 5 losses in a row!");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(PositionsTotal() > 0) return;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(emaFastHandle, 0, 0, 3, fast) < 3) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 3, slow) < 3) return;

   bool buy = fast[1] > slow[1] && fast[2] <= slow[2];
   bool sell = fast[1] < slow[1] && fast[2] >= slow[2];

   if(buy) Open(ORDER_TYPE_BUY);
   if(sell) Open(ORDER_TYPE_SELL);
}

void Open(ENUM_ORDER_TYPE type)
{
   double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type==ORDER_TYPE_BUY)? price - StopLossPoints * _Point : price + StopLossPoints * _Point;
   double tp = (type==ORDER_TYPE_BUY)? price + TakeProfitPoints * _Point : price - TakeProfitPoints * _Point;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = FixedLot;
   req.type = type;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 100;

   Print("GAMBLE ", EnumToString(type), " Lot ", FixedLot);
   if(!OrderSend(req, res))
      Print("FAILED ", GetLastError(), " ", res.comment);
   else
      Print("OPENED Ticket ", res.order, " Profit target $", TakeProfitPoints * 0.01 * FixedLot * 10);
}
