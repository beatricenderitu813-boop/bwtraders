//+------------------------------------------------------------------+
//| Simple Flipping Bot - Fixed No Warnings |
//| For XAUUSDm M5 - DEMO FIRST - Educational Only |
//+------------------------------------------------------------------+
#property strict

input double RiskPercent = 10.0;
input int StopLossPoints = 500;
input int TakeProfitPoints = 800;
input int EMA_Fast = 20;
input int EMA_Slow = 50;
input int RSI_Period = 14;
input double MaxDailyLossPercent = 30.0;

int emaFastHandle, emaSlowHandle, rsiHandle;
double dayStartBalance;
datetime lastDay;

//+------------------------------------------------------------------+
int OnInit()
  {
   emaFastHandle = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDay = iTime(_Symbol, PERIOD_D1, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(PositionsTotal() > 0) return;

   datetime currDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currDay!= lastDay)
     {
      lastDay = currDay;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }

   double currEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = dayStartBalance - currEquity;
   if(dailyLoss >= dayStartBalance * MaxDailyLossPercent / 100.0) return;

   double emaFast[], emaSlow[], rsi[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(emaFastHandle, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 3) return;

   bool buySignal = emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2] && rsi[1] > 55;
   bool sellSignal = emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2] && rsi[1] < 45;

   if(buySignal) OpenTrade(ORDER_TYPE_BUY);
   if(sellSignal) OpenTrade(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) tickValue = 1.0;
   double lot = riskMoney / (StopLossPoints * tickValue);
   lot = MathFloor(lot / 0.01) * 0.01;
   if(lot < 0.01) lot = 0.01;
   if(lot > 0.5) lot = 0.5;

   double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type==ORDER_TYPE_BUY)? price - StopLossPoints * _Point : price + StopLossPoints * _Point;
   double tp = (type==ORDER_TYPE_BUY)? price + TakeProfitPoints * _Point : price - TakeProfitPoints * _Point;

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = type;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 30;

   if(!OrderSend(req, res))
     {
      Print("OrderSend failed: ", GetLastError(), " - ", res.comment);
     }
  }
//+------------------------------------------------------------------+
