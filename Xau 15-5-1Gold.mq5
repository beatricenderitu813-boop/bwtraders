//+------------------------------------------------------------------+
//| Xau 15-5-1Gold DASHBOARD v2.1 TEST MODE |
//| Loose Pullback + NY Filter OFF + Progress in Experts |
//+------------------------------------------------------------------+
#property copyright "Gold Scalper v2.1"
#property version "2.10"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double Lots=0.05;
input double SL_Dollars=3.5;
input double TP_Dollars=7.0;
input double MaxSpreadPoints=600;
input int Magic=20250915;
input bool UseNYFilter=false;
input double PullbackMaxDist=3.0;

string BTN_NAME="BTN_GOLD_TOGGLE";
bool isActive=true;

int OnInit()
{
   CreateButton();
   CreateDashboard();
   Print("Gold Scalper v2.1 TEST MODE Loaded - NY Filter OFF, Loose Pullback - Dashboard ON");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int r)
{
   ObjectsDeleteAll(0,"DASH_");
   ObjectDelete(0,BTN_NAME);
}
void OnTick()
{
   UpdateDashboard();
   if(!isActive) return;
   if(!IsNewBar()) return;
   if(UseNYFilter &&!IsNYSession()) return;
   if((long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) > (long)MaxSpreadPoints) return;
   CheckAndTrade();
}
bool IsNewBar()
{
   static datetime lt=0;
   datetime cur=iTime(_Symbol,PERIOD_M1,0);
   if(cur!=lt){ lt=cur; return true; }
   return false;
}
bool IsNYSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(),dt);
   return (dt.hour>=13 && dt.hour<=22);
}
string Get15MTrend()
{
   double a[];
   ArraySetAsSeries(a,true);
   CopyBuffer(iMA(_Symbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE),0,0,2,a);
   double p=iClose(_Symbol,PERIOD_M15,1);
   if(p>a[0]) return "BULLISH";
   if(p<a[0]) return "BEARISH";
   return "NEUTRAL";
}
string Get5MPullback(string t)
{
   double ema[];
   ArraySetAsSeries(ema,true);
   CopyBuffer(iMA(_Symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE),0,0,2,ema);
   double c=iClose(_Symbol,PERIOD_M5,1);
   double dist=MathAbs(c-ema[0]);
   if(dist <= PullbackMaxDist) return "PULLBACK OK";
   if(t=="BULLISH" && c < ema[0]+PullbackMaxDist*2) return "PULLBACK OK (Near)";
   if(t=="BEARISH" && c > ema[0]-PullbackMaxDist*2) return "PULLBACK OK (Near)";
   return "WAITING PULLBACK";
}
string Get1MSignal()
{
   double o1=iOpen(_Symbol,PERIOD_M1,1), c1=iClose(_Symbol,PERIOD_M1,1);
   double o2=iOpen(_Symbol,PERIOD_M1,2), c2=iClose(_Symbol,PERIOD_M1,2);
   bool bullishEngulf = (c2 < o2 && c1 > o1 && c1 > o2 && o1 < c2);
   bool bearishEngulf = (c2 > o2 && c1 < o1 && c1 < o2 && o1 > c2);
   bool bullishPin = (c1 > o1 && (o1 - iLow(_Symbol,PERIOD_M1,1)) > (c1-o1)*1.5);
   bool bearishPin = (c1 < o1 && (iHigh(_Symbol,PERIOD_M1,1) - o1) > (o1-c1)*1.5);
   if(bullishEngulf || bullishPin) return "BULLISH ENGULFING";
   if(bearishEngulf || bearishPin) return "BEARISH ENGULFING";
   return "WAITING ENGULF";
}
void CheckAndTrade()
{
   if(PositionSelect(_Symbol)) return;
   string tr=Get15MTrend();
   string pb=Get5MPullback(tr);
   string si=Get1MSignal();
   bool pullbackOk = (StringFind(pb,"PULLBACK OK")>=0);
   bool buyCond = (tr=="BULLISH" && pullbackOk && StringFind(si,"BULLISH")>=0);
   bool sellCond = (tr=="BEARISH" && pullbackOk && StringFind(si,"BEARISH")>=0);
   if(buyCond || sellCond)
   {
      double price= buyCond? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl_dist=SL_Dollars/(Lots*100);
      double tp_dist=TP_Dollars/(Lots*100);
      double sl= buyCond? price - sl_dist : price + sl_dist;
      double tp= buyCond? price + tp_dist : price - tp_dist;
      trade.SetDeviationInPoints(500);
      if(buyCond) trade.Buy(Lots,_Symbol,price,sl,tp,"GOLD TEST BUY");
      else trade.Sell(Lots,_Symbol,price,sl,tp,"GOLD TEST SELL");
      Print("GOLD TRADE EXECUTED: ",buyCond?"BUY":"SELL"," @ ",price," | ",pb," + ",si);
   }
}
void CreateButton()
{
   ObjectCreate(0,BTN_NAME,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_XSIZE,120);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_YSIZE,30);
   ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,"STOP GOLD");
   ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,clrRed);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,BTN_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}
void CreateDashboard()
{
   for(int i=0;i<6;i++)
   {
      string n="DASH_"+IntegerToString(i);
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,60+i*20);
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   }
}
void UpdateDashboard()
{
   string tr=Get15MTrend();
   string pb=Get5MPullback(tr);
   string si=Get1MSignal();
   bool ny=IsNYSession();
   long sp=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   string L[6];
   L[0]="15M TREND: "+tr+" [TEST MODE v2.1]";
   L[1]="5M PULLBACK: "+pb;
   L[2]="1M SIGNAL: "+si;
   L[3]="NY SESSION: "+(ny?"ACTIVE":"WAITING")+(UseNYFilter?" (FILTER ON)":" (FILTER OFF - WILL TRADE)");
   L[4]="SPREAD: "+IntegerToString(sp)+" / Max "+DoubleToString(MaxSpreadPoints,0);
   L[5]="STATUS: "+(isActive?"SCANNING FOR TEST TRADE...":"STOPPED");
   for(int i=0;i<6;i++)
   {
      ObjectSetString(0,"DASH_"+IntegerToString(i),OBJPROP_TEXT,L[i]);
      color c=clrWhite;
      if(i==0) c=(tr=="BULLISH"?clrLime:tr=="BEARISH"?clrRed:clrYellow);
      if(i==1) c=(StringFind(pb,"PULLBACK OK")>=0?clrLime:clrYellow);
      if(i==2) c=(StringFind(si,"ENGULFING")>=0?clrLime:clrYellow);
      if(i==3) c=(UseNYFilter?(ny?clrLime:clrGray):clrLime);
      ObjectSetInteger(0,"DASH_"+IntegerToString(i),OBJPROP_COLOR,c);
   }
   static datetime ll=0;
   if(TimeCurrent()-ll>20)
   {
      ll=TimeCurrent();
      Print("PROGRESS | 15M:",tr," | 5M:",pb," | 1M:",si," | NY:",ny," FilterOFF:",!UseNYFilter);
   }
}
void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sp==BTN_NAME)
   {
      isActive=!isActive;
      ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,isActive?"STOP GOLD":"START GOLD");
      ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,isActive?clrRed:clrGreen);
      Print(isActive?"EA RESUMED":"EA STOPPED BY BUTTON");
   }
}
