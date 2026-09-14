#property strict
input double LotSize = 0.01;
input double ProfitPerTradeUSD = 0.40;
input double StopLossPerTradeUSD = 1.00;
input int MaxHoldMinutes = 60;
input int MaxOpenPositions = 2;
input int EMA_Fast = 9;
input int EMA_Slow = 21;
int emaFastHandle, emaSlowHandle;
int OnInit(){ emaFastHandle=iMA(_Symbol,PERIOD_M1,EMA_Fast,0,MODE_EMA,PRICE_CLOSE); emaSlowHandle=iMA(_Symbol,PERIOD_M1,EMA_Slow,0,MODE_EMA,PRICE_CLOSE); return(INIT_SUCCEEDED); }
void OnTick(){
   datetime now=TimeCurrent();
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong ticket=PositionGetTicket(i); if(ticket==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double profit=PositionGetDouble(POSITION_PROFIT); datetime ot=(datetime)PositionGetInteger(POSITION_TIME); int m=(int)((now-ot)/60); if(profit>=ProfitPerTradeUSD || profit<=-StopLossPerTradeUSD || m>=MaxHoldMinutes){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.position=ticket; req.price=(req.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=100; bool ok=OrderSend(req,res); if(ok) Print("Closed profit ",profit); } }
   int cnt=0; for(int i=0;i<PositionsTotal();i++){ if(PositionGetTicket(i)==0) continue; if(PositionGetString(POSITION_SYMBOL)==_Symbol) cnt++; } if(cnt>=MaxOpenPositions) return;
   double fast[]; double slow[]; ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true); if(CopyBuffer(emaFastHandle,0,0,2,fast)<2) return; if(CopyBuffer(emaSlowHandle,0,0,2,slow)<2) return; double o=iOpen(_Symbol,PERIOD_M1,0); double b=SymbolInfoDouble(_Symbol,SYMBOL_BID); if(o==0) return; if(fast[0]>slow[0] && b>o){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize; req.type=ORDER_TYPE_BUY; req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK); req.deviation=100; bool ok=OrderSend(req,res); if(ok) Print("Buy opened"); } if(fast[0]<slow[0] && b<o){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=LotSize; req.type=ORDER_TYPE_SELL; req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=100; bool ok=OrderSend(req,res); if(ok) Print("Sell opened"); } }
