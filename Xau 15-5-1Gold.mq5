// Xau 15-5-1Gold Dashboard v2.00 - Full file ready
// Save as: Xau_15-5-1Gold_Dashboard.mq5 then Compile (F7)

#property version "2.00"
#include <Trade/Trade.mqh>
CTrade trade;

input double Lots=0.05; input double SL_Dollars=3.5; input double TP_Dollars=7.0;
input double MaxSpreadPoints=400; input int Magic=20250915; input bool UseNYFilter=true;

string BTN_NAME="BTN_GOLD_TOGGLE"; bool isActive=true;

int OnInit(){ CreateButton(); CreateDashboard(); Print("Gold Scalper Loaded - Ready for NY Session - Dashboard ON"); return(INIT_SUCCEEDED); }
void OnDeinit(const int r){ ObjectsDeleteAll(0,"DASH_"); ObjectDelete(0,BTN_NAME); }
void OnTick(){ UpdateDashboard(); if(!isActive) return; if(!IsNewBar()) return; if(UseNYFilter &&!IsNYSession()) return; if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>MaxSpreadPoints) return; CheckAndTrade(); }

bool IsNewBar(){ static datetime lt=0; datetime cur=iTime(_Symbol,PERIOD_M1,0); if(cur!=lt){lt=cur; return true;} return false; }
bool IsNYSession(){ MqlDateTime dt; TimeToStruct(TimeGMT(),dt); return (dt.hour>=13 && dt.hour<=22); }

string Get15MTrend(){ double a[]; ArraySetAsSeries(a,true); CopyBuffer(iMA(_Symbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE),0,0,2,a); double p=iClose(_Symbol,PERIOD_M15,1); return (p>a[0]?"BULLISH":p<a[0]?"BEARISH":"NEUTRAL"); }
string Get5MPullback(string t){ double a[]; ArraySetAsSeries(a,true); CopyBuffer(iMA(_Symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE),0,0,2,a); double c=iClose(_Symbol,PERIOD_M5,1); double l=iLow(_Symbol,PERIOD_M5,1); double h=iHigh(_Symbol,PERIOD_M5,1); if(t=="BULLISH") return (l<=a[0] && c>a[0]? "PULLBACK OK" : "WAITING PULLBACK"); if(t=="BEARISH") return (h>=a[0] && c<a[0]? "PULLBACK OK" : "WAITING PULLBACK"); return "WAITING"; }
string Get1MSignal(){ double o1=iOpen(_Symbol,PERIOD_M1,1),c1=iClose(_Symbol,PERIOD_M1,1),o2=iOpen(_Symbol,PERIOD_M1,2),c2=iClose(_Symbol,PERIOD_M1,2); bool b=(c2<o2 && c1>o1 && c1>o2 && o1<c2); bool s=(c2>o2 && c1<o1 && c1<o2 && o1>c2); return b?"BULLISH ENGULFING":s?"BEARISH ENGULFING":"WAITING ENGULF"; }

void CheckAndTrade(){ string tr=Get15MTrend(); string pb=Get5MPullback(tr); string si=Get1MSignal(); bool buy=(tr=="BULLISH" && pb=="PULLBACK OK" && si=="BULLISH ENGULFING"); bool sell=(tr=="BEARISH" && pb=="PULLBACK OK" && si=="BEARISH ENGULFING"); if(buy||sell){ double pr=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); double sd=SL_Dollars/(Lots*100); double td=TP_Dollars/(Lots*100); double sl=buy?pr-sd:pr+sd; double tp=buy?pr+td:pr-td; if(buy) trade.Buy(Lots,_Symbol,pr,sl,tp); else trade.Sell(Lots,_Symbol,pr,sl,tp); Print("GOLD TRADE EXECUTED: ",buy?"BUY":"SELL"," @ ",pr); } }

void CreateButton(){ ObjectCreate(0,BTN_NAME,OBJ_BUTTON,0,0,0); ObjectSetInteger(0,BTN_NAME,OBJPROP_XDISTANCE,10); ObjectSetInteger(0,BTN_NAME,OBJPROP_YDISTANCE,20); ObjectSetInteger(0,BTN_NAME,OBJPROP_XSIZE,120); ObjectSetInteger(0,BTN_NAME,OBJPROP_YSIZE,30); ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,"STOP GOLD"); ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,clrRed); ObjectSetInteger(0,BTN_NAME,OBJPROP_COLOR,clrWhite); }
void CreateDashboard(){ for(int i=0;i<6;i++){ string n="DASH_"+IntegerToString(i); ObjectCreate(0,n,OBJ_LABEL,0,0,0); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,10); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,60+i*20); ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9); ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite); } }
void UpdateDashboard(){ string tr=Get15MTrend(); string pb=Get5MPullback(tr); string si=Get1MSignal(); bool ny=IsNYSession(); long sp=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); string L[6]; L[0]="15M TREND: "+tr; L[1]="5M PULLBACK: "+pb; L[2]="1M SIGNAL: "+si; L[3]="NY SESSION: "+(ny?"ACTIVE":"WAITING (13-22 GMT)"); L[4]="SPREAD: "+IntegerToString(sp); L[5]="STATUS: "+(isActive?"SCANNING...":"STOPPED"); for(int i=0;i<6;i++){ ObjectSetString(0,"DASH_"+IntegerToString(i),OBJPROP_TEXT,L[i]); color c=clrWhite; if(i==0) c=(tr=="BULLISH"?clrLime:tr=="BEARISH"?clrRed:clrYellow); if(i==1) c=(pb=="PULLBACK OK"?clrLime:clrYellow); if(i==2) c=(StringFind(si,"ENGULFING")>=0?clrLime:clrYellow); if(i==3) c=(ny?clrLime:clrGray); ObjectSetInteger(0,"DASH_"+IntegerToString(i),OBJPROP_COLOR,c); } static datetime ll=0; if(TimeCurrent()-ll>30){ ll=TimeCurrent(); Print("PROGRESS | 15M:",tr," | 5M:",pb," | 1M:",si," | NY:",ny); } }
void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp){ if(id==CHARTEVENT_OBJECT_CLICK && sp==BTN_NAME){ isActive=!isActive; ObjectSetString(0,BTN_NAME,OBJPROP_TEXT,isActive?"STOP GOLD":"START GOLD"); ObjectSetInteger(0,BTN_NAME,OBJPROP_BGCOLOR,isActive?clrRed:clrGreen); Print(isActive?"EA RESUMED":"EA STOPPED"); } }
