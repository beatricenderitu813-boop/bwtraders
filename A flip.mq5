//+------------------------------------------------------------------+
//| Simple Flipping Bot - Educational Template |
//| For XAUUSDm M5 - Use ONLY ON DEMO FIRST |
//| This is NOT a no-loss bot. Trading is risky. |
//+------------------------------------------------------------------+
#property strict

input double RiskPercent = 10.0; // Risk per trade % (10 = $1 on $10 acc)
input int StopLossPoints = 500; // SL in points (500 = 50 pips for Gold)
input int TakeProfitPoints = 800; // TP in points (800 = 80 pips) -> 1:1.6 RR
input int EMA_Fast = 20;
input int EMA_Slow = 50;
input int RSI_Period = 14;
input double MaxDailyLossPercent = 30.0; // Stop bot if -30% today

int emaHandle, rsiHandle;
double dayStartBalance;
datetime lastDay;

//+------------------------------------------------------------------+
int OnInit()
  {
   emaHandle = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDay = iTime(_Symbol, PERIOD_D1, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewDayCheck()) return;
   if(PositionsTotal() > 0) return; // 1 trade at a time

   // Daily protector
   double currEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = dayStartBalance - currEquity;
   if(dailyLoss >= dayStartBalance * MaxDailyLossPercent / 100.0) return;

   double emaFast[], emaSlow[], rsi[];
   CopyBuffer(emaHandle, 0, 0, 3, emaFast);
   CopyBuffer(iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 3, emaSlow);
   CopyBuffer(rsiHandle, 0, 0, 3, rsi);
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true); ArraySetAsSeries(rsi, true);

   // Entry conditions
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
   double lot = riskMoney / (StopLossPoints * tickValue);

   lot = MathFloor(lot / 0.01) * 0.01; // Round to 0.01
   if(lot < 0.01) lot = 0.01;
   if(lot > 0.5) lot = 0.5; // Safety cap for $10 account

   double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type==ORDER_TYPE_BUY)? price - StopLossPoints * _Point : price + StopLossPoints * _Point;
   double tp = (type==ORDER_TYPE_BUY)? price + TakeProfitPoints * _Point : price - TakeProfitPoints * _Point;

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = type;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 30;
   OrderSend(req, res);
  }

//+------------------------------------------------------------------+
bool IsNewDayCheck()
  {
   datetime currDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currDay!= lastDay)
     {
      lastDay = currDay;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
   return true;
  }
//+------------------------------------------------------------------+
