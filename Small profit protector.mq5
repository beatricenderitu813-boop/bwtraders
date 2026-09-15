//+------------------------------------------------------------------+
//| Small Profit Protector - GOLD - Both Directions |
//+------------------------------------------------------------------+
#property strict

input double Lots = 0.01;
input int FastEMA = 10;
input int SlowEMA = 20;
input int TakeProfitPoints = 80;
input int StopLossPoints = 150;
input int BreakEvenPoints = 30;
input int TrailingStart = 50;
input int TrailingStep = 20;

int ema_fast, ema_slow;
datetime lastTradeTime=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   ema_fast = iMA(_Symbol, PERIOD_M5, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow = iMA(_Symbol, PERIOD_M5, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema_fast);
   IndicatorRelease(ema_slow);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   if(PositionSelect(_Symbol))
     {
      ProtectProfit();
      return;
     }
   if(lastTradeTime == iTime(_Symbol, PERIOD_M5, 0)) return;

   double fast1[], slow1[];
   CopyBuffer(ema_fast,0,0,3,fast1); ArraySetAsSeries(fast1,true);
   CopyBuffer(ema_slow,0,0,3,slow1); ArraySetAsSeries(slow1,true);

   if(fast1[1] > slow1[1] && fast1[2] <= slow1[2])
     {
      OpenTrade(ORDER_TYPE_BUY);
     }
   else if(fast1[1] < slow1[1] && fast1[2] >= slow1[2])
     {
      OpenTrade(ORDER_TYPE_SELL);
     }
  }
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=0, tp=0;
   if(type==ORDER_TYPE_BUY)
     {
      sl = price - StopLossPoints * _Point;
      tp = price + TakeProfitPoints * _Point;
     }
   else
     {
      sl = price + StopLossPoints * _Point;
      tp = price - TakeProfitPoints * _Point;
     }
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = Lots;
   req.type = type;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 30;
   req.magic = 1111;
   if(!OrderSend(req,res))
      Print("OrderSend failed: ", res.retcode);
   else
      lastTradeTime = iTime(_Symbol, PERIOD_M5, 0);
  }
//+------------------------------------------------------------------+
void ProtectProfit()
  {
   double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   long type = PositionGetInteger(POSITION_TYPE);
   double profitPoints = 0;
   if(type==POSITION_TYPE_BUY)
      profitPoints = (currentPrice - posPrice) / _Point;
   else
      profitPoints = (posPrice - currentPrice) / _Point;

   if(profitPoints >= BreakEvenPoints)
     {
      double newSL = posPrice + (type==POSITION_TYPE_BUY? 5*_Point : -5*_Point);
      if(type==POSITION_TYPE_BUY && (posSL < posPrice || posSL==0))
         ModifySL(newSL);
      else if(type==POSITION_TYPE_SELL && (posSL > posPrice || posSL==0))
         ModifySL(newSL);
     }
   if(profitPoints >= TrailingStart)
     {
      double newSL = 0;
      if(type==POSITION_TYPE_BUY)
         newSL = currentPrice - TrailingStep * _Point;
      else
         newSL = currentPrice + TrailingStep * _Point;
      if((type==POSITION_TYPE_BUY && newSL > posSL) || (type==POSITION_TYPE_SELL && newSL < posSL))
         ModifySL(newSL);
     }
  }
//+------------------------------------------------------------------+
void ModifySL(double newSL)
  {
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   req.action = TRADE_ACTION_SLTP;
   req.symbol = _Symbol;
   req.sl = newSL;
   req.tp = PositionGetDouble(POSITION_TP);
   if(!OrderSend(req,res))
      Print("Modify failed: ", res.retcode);
  }
//+------------------------------------------------------------------+
