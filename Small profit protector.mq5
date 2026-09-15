//+------------------------------------------------------------------+
//| Small Profit Protector - GOLD - Both Directions                  |
//| For $10 account, 0.01 lot, protects small profits                |
//+------------------------------------------------------------------+
#property strict

input double Lots = 0.01;
input int FastEMA = 10;
input int SlowEMA = 20;
input int TakeProfitPoints = 80;  // $0.80 on Gold 0.01 lot
input int StopLossPoints = 150;   // $1.50 protection
input int BreakEvenPoints = 30;   // Move SL to entry at +30
input int TrailingStart = 50;     // Start trailing at +50
input int TrailingStep = 20;      // Trail by 20

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
   if(PositionSelect(_Symbol)) // Only 1 trade at a time - protect first
     {
      ProtectProfit();
      return;
     }

   // Prevent multiple trades on same bar
   if(lastTradeTime == iTime(_Symbol, PERIOD_M5, 0)) return;

   double fast1[], fast2[], slow1[], slow2[];
   CopyBuffer(ema_fast,0,0,3,fast1); ArraySetAsSeries(fast1,true);
   CopyBuffer(ema_slow,0,0,3,slow1); ArraySetAsSeries(slow1,true);

   // Buy: fast crossed above slow
   if(fast1[1] > slow1[1] && fast1[2] <= slow1[2])
     {
      OpenTrade(ORDER_TYPE_BUY);
     }
   // Sell: fast crossed below slow
   else if(fast1[1] < slow1[1] && fast1[2] >= slow1[2])
     {
      OpenTrade(ORDER_TYPE_SELL);
     }
  }
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   double price = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
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

   if(OrderSend(req,res))
     {
      lastTradeTime = iTime(_Symbol, PERIOD_M5, 0);
      Print("Trade Opened: ", EnumToString(type));
     }
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

   // 1. BreakEven - protect small profit
   if(profitPoints >= BreakEvenPoints)
     {
      double newSL = posPrice + (type==POSITION_TYPE_BUY ? 5*_Point : -5*_Point); // small lock
      if(type==POSITION_TYPE_BUY && (posSL < posPrice || posSL==0) )
        {
         ModifySL(newSL);
        }
      else if(type==POSITION_TYPE_SELL && (posSL > posPrice || posSL==0))
        {
         ModifySL(newSL);
        }
     }

   // 2. Trailing - lock small small profits
   if(profitPoints >= TrailingStart)
     {
      double newSL = 0;
      if(type==POSITION_TYPE_BUY)
         newSL = currentPrice - TrailingStep * _Point;
      else
         newSL = currentPrice + TrailingStep * _Point;

      if( (type==POSITION_TYPE_BUY && newSL > posSL) || (type==POSITION_TYPE_SELL && newSL < posSL) )
        {
         ModifySL(newSL);
        }
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
   OrderSend(req,res);
  }
//+------------------------------------------------------------------+
