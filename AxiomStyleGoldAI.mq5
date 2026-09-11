//+------------------------------------------------------------------+
//|                 AxiomStyleGoldAI.mq5                             |
//|        Independent Axiom FX-style XAUUSD MT5 Expert Advisor      |
//|                                                                    |
//|  Clean-room implementation based on publicly described concepts. |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Independent Axiom FX-style gold scalping EA"

//--- Trading library
#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS
//====================================================================

//--- General
input string InpTradeSymbol          = "XAUUSD";
input long   InpMagicNumber          = 11092026;
input bool   InpStartAutomatically    = true;

//--- Risk
input double InpRiskPercent          = 0.50;
input double InpMaxDailyLossPercent  = 2.00;
input double InpMaxDrawdownPercent   = 5.00;

//--- Entry
input ENUM_TIMEFRAMES InpSignalTF    = PERIOD_M1;
input double InpMinimumScore         = 70.0;
input int    InpLookbackBars         = 20;
input int    InpVolumeLookback       = 10;

//--- Stop / target
input double InpStopLossPoints       = 300.0;
input double InpRewardRisk           = 1.50;

//--- Trading limits
input int    InpMaxOpenPositions     = 1;
input int    InpMaxSpreadPoints      = 80;
input int    InpSlippagePoints       = 30;

//--- Session
input bool   InpUseSessionFilter     = true;
input int    InpSessionStartHour     = 7;
input int    InpSessionEndHour       = 22;

//--- Price-action settings
input double InpBreakoutFactor       = 0.15;
input double InpMomentumFactor       = 0.60;

//--- Display
input bool   InpShowProgress         = true;

//====================================================================
// GLOBAL VARIABLES
//====================================================================

bool     g_running             = false;
bool     g_dailyBlocked        = false;
bool     g_drawdownBlocked     = false;

double   g_dayStartEquity      = 0.0;
double   g_peakEquity          = 0.0;

datetime g_dayStartTime        = 0;
datetime g_lastSignalTime      = 0;

string   g_status              = "INITIALIZING";

//====================================================================
// INITIALIZATION
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   g_dayStartTime   = GetDayStart();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity     = g_dayStartEquity;

   g_running = InpStartAutomatically;

   Print("=================================================");
   Print("AXIOM STYLE GOLD AI INITIALIZED");
   Print("Symbol: ", InpTradeSymbol);
   Print("Signal timeframe: ", EnumToString(InpSignalTF));
   Print("Risk: ", DoubleToString(InpRiskPercent,2), "%");
   Print("Minimum score: ", DoubleToString(InpMinimumScore,1));
   Print("=================================================");

   return(INIT_SUCCEEDED);
}

//====================================================================
// DEINITIALIZATION
//====================================================================

void OnDeinit(const int reason)
{
   Comment("");
   Print("Axiom Style Gold AI stopped. Reason = ", reason);
}

//====================================================================
// MAIN TICK FUNCTION
//====================================================================

void OnTick()
{
   UpdateDailyValues();

   if(!IsCorrectSymbol())
   {
      g_status = "Attach EA to XAUUSD";
      ShowProgress();
      return;
   }

   if(!g_running)
   {
      g_status = "STOPPED";
      ShowProgress();
      return;
   }

   if(!TradingEnvironmentOK())
   {
      ShowProgress();
      return;
   }

   if(CheckProtectionLimits())
   {
      ShowProgress();
      return;
   }

   if(!IsTradingSession())
   {
      g_status = "Outside trading session";
      ShowProgress();
      return;
   }

   if(!SpreadOK())
   {
      g_status = "Spread too high";
      ShowProgress();
      return;
   }

   int positions = CountOurPositions();

   if(positions >= InpMaxOpenPositions)
   {
      g_status = "Position active - managing";
      ManageOpenPositions();
      ShowProgress();
      return;
   }

   ManageOpenPositions();

   //--- Analyze the current live market.
   double buyScore  = 0.0;
   double sellScore = 0.0;

   AnalyzeMarket(buyScore, sellScore);

   ShowScores(buyScore, sellScore);

   //--- Buy signal
   if(buyScore >= InpMinimumScore &&
      buyScore > sellScore)
   {
      if(g_lastSignalTime != iTime(_Symbol, InpSignalTF, 0))
      {
         if(OpenBuy(buyScore))
         {
            g_lastSignalTime = iTime(_Symbol, InpSignalTF, 0);
         }
      }
   }

   //--- Sell signal
   else if(sellScore >= InpMinimumScore &&
           sellScore > buyScore)
   {
      if(g_lastSignalTime != iTime(_Symbol, InpSignalTF, 0))
      {
         if(OpenSell(sellScore))
         {
            g_lastSignalTime = iTime(_Symbol, InpSignalTF, 0);
         }
      }
   }
}

//====================================================================
// SYMBOL CHECK
//====================================================================

bool IsCorrectSymbol()
{
   string current = _Symbol;

   if(StringFind(current, "XAU") >= 0)
      return true;

   if(StringFind(current, "GOLD") >= 0)
      return true;

   return false;
}

//====================================================================
// DAY START
//====================================================================

datetime GetDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   return StructToTime(dt);
}

//====================================================================
// UPDATE DAILY VALUES
//====================================================================

void UpdateDailyValues()
{
   datetime today = GetDayStart();

   if(today != g_dayStartTime)
   {
      g_dayStartTime   = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      g_dailyBlocked   = false;
      g_drawdownBlocked = false;

      Print("New trading day. Daily protection reset.");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > g_peakEquity)
      g_peakEquity = equity;
}

//====================================================================
// PROTECTION LIMITS
//====================================================================

bool CheckProtectionLimits()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = equity;

   if(g_peakEquity <= 0.0)
      g_peakEquity = equity;

   double dailyLossPercent =
      ((g_dayStartEquity - equity) / g_dayStartEquity) * 100.0;

   double drawdownPercent =
      ((g_peakEquity - equity) / g_peakEquity) * 100.0;

   if(dailyLossPercent >= InpMaxDailyLossPercent)
   {
      g_dailyBlocked = true;
      g_status = "DAILY LOSS PROTECTION";
      return true;
   }

   if(drawdownPercent >= InpMaxDrawdownPercent)
   {
      g_drawdownBlocked = true;
      g_status = "MAX DRAWDOWN PROTECTION";
      return true;
   }

   if(g_dailyBlocked || g_drawdownBlocked)
      return true;

   return false;
}

//====================================================================
// TRADING ENVIRONMENT
//====================================================================

bool TradingEnvironmentOK()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      g_status = "Terminal trading disabled";
      return false;
   }

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      g_status = "EA trading disabled";
      return false;
   }

   return true;
}

//====================================================================
// SESSION FILTER
//====================================================================

bool IsTradingSession()
{
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int hour = dt.hour;

   if(InpSessionStartHour < InpSessionEndHour)
   {
      if(hour >= InpSessionStartHour &&
         hour < InpSessionEndHour)
         return true;
   }
   else
   {
      if(hour >= InpSessionStartHour ||
         hour < InpSessionEndHour)
         return true;
   }

   return false;
}

//====================================================================
// SPREAD
//====================================================================

bool SpreadOK()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0)
      return false;

   double spreadPoints = (ask - bid) / _Point;

   return(spreadPoints <= InpMaxSpreadPoints);
}

//====================================================================
// POSITION COUNT
//====================================================================

int CountOurPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol && magic == InpMagicNumber)
         count++;
   }

   return count;
}

//====================================================================
// END PART 1
//====================================================================//====================================================================
// MARKET ANALYSIS ENGINE
//====================================================================

void AnalyzeMarket(double &buyScore, double &sellScore)
{
   buyScore  = 0.0;
   sellScore = 0.0;

   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   int copied = CopyRates(_Symbol,
                          InpSignalTF,
                          0,
                          InpLookbackBars + 5,
                          rates);

   if(copied < InpLookbackBars)
   {
      g_status = "Waiting for market data";
      return;
   }

   //---------------------------------------------------------------
   // Current live candle
   //---------------------------------------------------------------

   double open0  = rates[0].open;
   double high0  = rates[0].high;
   double low0   = rates[0].low;
   double close0 = rates[0].close;

   double range0 = high0 - low0;

   if(range0 <= 0.0)
      return;

   double body0 = MathAbs(close0 - open0);

   double upperWick =
      high0 - MathMax(open0, close0);

   double lowerWick =
      MathMin(open0, close0) - low0;

   //---------------------------------------------------------------
   // 1. CURRENT PRICE DIRECTION
   //---------------------------------------------------------------

   if(close0 > open0)
      buyScore += 20.0;

   if(close0 < open0)
      sellScore += 20.0;

   //---------------------------------------------------------------
   // 2. CANDLE BODY MOMENTUM
   //---------------------------------------------------------------

   double bodyRatio = body0 / range0;

   if(bodyRatio >= InpMomentumFactor)
   {
      if(close0 > open0)
         buyScore += 15.0;

      if(close0 < open0)
         sellScore += 15.0;
   }

   //---------------------------------------------------------------
   // 3. WICK / REJECTION ANALYSIS
   //---------------------------------------------------------------

   if(lowerWick > body0 * 1.20 &&
      lowerWick > upperWick)
   {
      buyScore += 12.0;
   }

   if(upperWick > body0 * 1.20 &&
      upperWick > lowerWick)
   {
      sellScore += 12.0;
   }

   //---------------------------------------------------------------
   // 4. RECENT HIGH / LOW STRUCTURE
   //---------------------------------------------------------------

   double recentHigh = rates[1].high;
   double recentLow  = rates[1].low;

   for(int i = 1; i < InpLookbackBars && i < copied; i++)
   {
      if(rates[i].high > recentHigh)
         recentHigh = rates[i].high;

      if(rates[i].low < recentLow)
         recentLow = rates[i].low;
   }

   //---------------------------------------------------------------
   // Breakout pressure
   //---------------------------------------------------------------

   double breakoutDistance =
      range0 * InpBreakoutFactor;

   if(close0 > recentHigh - breakoutDistance)
      buyScore += 15.0;

   if(close0 < recentLow + breakoutDistance)
      sellScore += 15.0;

   //---------------------------------------------------------------
   // 5. SHORT-TERM MOMENTUM
   //---------------------------------------------------------------

   int bullishBars = 0;
   int bearishBars = 0;

   int momentumBars = MathMin(5, copied - 1);

   for(int i = 1; i <= momentumBars; i++)
   {
      if(rates[i].close > rates[i].open)
         bullishBars++;

      if(rates[i].close < rates[i].open)
         bearishBars++;
   }

   if(bullishBars >= 3)
      buyScore += 10.0;

   if(bearishBars >= 3)
      sellScore += 10.0;

   //---------------------------------------------------------------
   // 6. TICK VOLUME ANALYSIS
   //---------------------------------------------------------------

   double averageVolume = 0.0;

   int volumeCount =
      MathMin(InpVolumeLookback, copied - 1);

   for(int i = 1; i <= volumeCount; i++)
      averageVolume += (double)rates[i].tick_volume;

   if(volumeCount > 0)
      averageVolume /= volumeCount;

   double currentVolume =
      (double)rates[0].tick_volume;

   if(averageVolume > 0.0)
   {
      if(currentVolume > averageVolume * 1.20)
      {
         if(close0 > open0)
            buyScore += 13.0;

         if(close0 < open0)
            sellScore += 13.0;
      }
   }

   //---------------------------------------------------------------
   // 7. PRICE LOCATION INSIDE RECENT RANGE
   //---------------------------------------------------------------

   double totalRange = recentHigh - recentLow;

   if(totalRange > 0.0)
   {
      double location =
         (close0 - recentLow) / totalRange;

      if(location >= 0.70)
         buyScore += 5.0;

      if(location <= 0.30)
         sellScore += 5.0;
   }

   //---------------------------------------------------------------
   // 8. MULTI-CANDLE DIRECTION
   //---------------------------------------------------------------

   double firstClose = rates[1].close;
   double olderClose = rates[momentumBars].close;

   if(firstClose > olderClose)
      buyScore += 5.0;

   if(firstClose < olderClose)
      sellScore += 5.0;

   //---------------------------------------------------------------
   // Cap scores
   //---------------------------------------------------------------

   if(buyScore > 100.0)
      buyScore = 100.0;

   if(sellScore > 100.0)
      sellScore = 100.0;

   g_status = "Scanning live XAUUSD";
}

//====================================================================
// LOT SIZE CALCULATION
//====================================================================

double CalculateLotSize(double stopDistancePoints)
{
   if(stopDistancePoints <= 0.0)
      return 0.0;

   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double riskMoney =
      balance * (InpRiskPercent / 100.0);

   double tickSize =
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double volumeStep =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double minVolume =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double maxVolume =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0.0 ||
      tickValue <= 0.0 ||
      volumeStep <= 0.0)
   {
      return minVolume;
   }

   double priceDistance =
      stopDistancePoints * _Point;

   double lossPerLot =
      (priceDistance / tickSize) * tickValue;

   if(lossPerLot <= 0.0)
      return minVolume;

   double lots =
      riskMoney / lossPerLot;

   lots =
      MathFloor(lots / volumeStep) * volumeStep;

   if(lots < minVolume)
      lots = minVolume;

   if(lots > maxVolume)
      lots = maxVolume;

   return NormalizeVolume(lots);
}

//====================================================================
// NORMALIZE VOLUME
//====================================================================

double NormalizeVolume(double volume)
{
   double step =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double minLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)
      return volume;

   volume =
      MathFloor(volume / step) * step;

   if(volume < minLot)
      volume = minLot;

   if(volume > maxLot)
      volume = maxLot;

   int digits = 0;

   double testStep = step;

   while(testStep < 1.0 && digits < 8)
   {
      testStep *= 10.0;
      digits++;
   }

   return NormalizeDouble(volume, digits);
}

//====================================================================
// BUY ENTRY
//====================================================================

bool OpenBuy(double score)
{
   double ask =
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ask <= 0.0)
      return false;

   double stopDistance =
      InpStopLossPoints * _Point;

   double sl =
      ask - stopDistance;

   double tp =
      ask + stopDistance * InpRewardRisk;

   double lots =
      CalculateLotSize(InpStopLossPoints);

   if(lots <= 0.0)
   {
      Print("BUY blocked: invalid lot size.");
      return false;
   }

   if(!StopsAreValid(ask, sl, tp, true))
   {
      Print("BUY blocked: invalid stop levels.");
      return false;
   }

   ResetLastError();

   bool result =
      trade.Buy(lots,
                _Symbol,
                0.0,
                NormalizeDouble(sl, _Digits),
                NormalizeDouble(tp, _Digits),
                "AXIOM_STYLE_BUY");

   if(result)
   {
      Print("==============================================");
      Print("AXIOM STYLE BUY EXECUTED");
      Print("Score: ", DoubleToString(score,1));
      Print("Lots: ", DoubleToString(lots,2));
      Print("Entry: ", DoubleToString(ask,_Digits));
      Print("SL: ", DoubleToString(sl,_Digits));
      Print("TP: ", DoubleToString(tp,_Digits));
      Print("==============================================");

      g_status = "BUY EXECUTED";
      return true;
   }

   Print("BUY FAILED. Retcode = ",
         trade.ResultRetcode(),
         " / ",
         trade.ResultRetcodeDescription());

   return false;
}

//====================================================================
// SELL ENTRY
//====================================================================

bool OpenSell(double score)
{
   double bid =
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   double stopDistance =
      InpStopLossPoints * _Point;

   double sl =
      bid + stopDistance;

   double tp =
      bid - stopDistance * InpRewardRisk;

   double lots =
      CalculateLotSize(InpStopLossPoints);

   if(lots <= 0.0)
   {
      Print("SELL blocked: invalid lot size.");
      return false;
   }

   if(!StopsAreValid(bid, sl, tp, false))
   {
      Print("SELL blocked: invalid stop levels.");
      return false;
   }

   ResetLastError();

   bool result =
      trade.Sell(lots,
                 _Symbol,
                 0.0,
                 NormalizeDouble(sl, _Digits),
                 NormalizeDouble(tp, _Digits),
                 "AXIOM_STYLE_SELL");

   if(result)
   {
      Print("==============================================");
      Print("AXIOM STYLE SELL EXECUTED");
      Print("Score: ", DoubleToString(score,1));
      Print("Lots: ", DoubleToString(lots,2));
      Print("Entry: ", DoubleToString(bid,_Digits));
      Print("SL: ", DoubleToString(sl,_Digits));
      Print("TP: ", DoubleToString(tp,_Digits));
      Print("==============================================");

      g_status = "SELL EXECUTED";
      return true;
   }

   Print("SELL FAILED. Retcode = ",
         trade.ResultRetcode(),
         " / ",
         trade.ResultRetcodeDescription());

   return false;
}

//====================================================================
// STOP VALIDATION
//====================================================================

bool StopsAreValid(double entry,
                   double sl,
                   double tp,
                   bool buy)
{
   long stopLevel =
      SymbolInfoInteger(_Symbol,
                        SYMBOL_TRADE_STOPS_LEVEL);

   double minimumDistance =
      stopLevel * _Point;

   if(buy)
   {
      if((entry - sl) < minimumDistance)
         return false;

      if((tp - entry) < minimumDistance)
         return false;
   }
   else
   {
      if((sl - entry) < minimumDistance)
         return false;

      if((entry - tp) < minimumDistance)
         return false;
   }

   return true;
}

//====================================================================
// END PART 2
//====================================================================//====================================================================
// OPEN POSITION MANAGEMENT
//====================================================================

void ManageOpenPositions()
{
   int managed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol ||
         magic != InpMagicNumber)
         continue;

      managed++;

      double profit =
         PositionGetDouble(POSITION_PROFIT);

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);

      // The broker's SL/TP handle normal exits.
      // We deliberately do not manually close profitable
      // positions here.
      //
      // This keeps the EA simple and avoids unnecessary
      // tick-by-tick closing/reopening.

      if(type == POSITION_TYPE_BUY)
      {
         if(profit > 0.0)
            g_status = "BUY in profit - protected";
         else
            g_status = "BUY active";
      }

      if(type == POSITION_TYPE_SELL)
      {
         if(profit > 0.0)
            g_status = "SELL in profit - protected";
         else
            g_status = "SELL active";
      }
   }

   if(managed == 0)
      g_status = "Scanning live XAUUSD";
}

//====================================================================
// DISPLAY
//====================================================================

void ShowScores(double buyScore,
                double sellScore)
{
   if(!InpShowProgress)
      return;

   string text =
      "\n"
      "========================================\n"
      "       AXIOM STYLE GOLD AI\n"
      "========================================\n"
      "Symbol: " + _Symbol + "\n"
      "Timeframe: " +
      EnumToString(InpSignalTF) + "\n"
      "\n"
      "BUY SCORE : " +
      DoubleToString(buyScore,1) + "%\n"
      "SELL SCORE: " +
      DoubleToString(sellScore,1) + "%\n"
      "Required  : " +
      DoubleToString(InpMinimumScore,1) + "%\n"
      "\n"
      "Status: " + g_status + "\n"
      "Positions: " +
      IntegerToString(CountOurPositions()) + "\n"
      "\n"
      "Risk: " +
      DoubleToString(InpRiskPercent,2) + "%\n"
      "Daily limit: " +
      DoubleToString(InpMaxDailyLossPercent,2) + "%\n"
      "Max DD: " +
      DoubleToString(InpMaxDrawdownPercent,2) + "%\n"
      "========================================";

   Comment(text);
}

//====================================================================
// PROGRESS DISPLAY
//====================================================================

void ShowProgress()
{
   if(!InpShowProgress)
      return;

   string text =
      "\n"
      "========================================\n"
      "       AXIOM STYLE GOLD AI\n"
      "========================================\n"
      "Symbol: " + _Symbol + "\n"
      "Timeframe: " +
      EnumToString(InpSignalTF) + "\n"
      "\n"
      "STATUS: " + g_status + "\n"
      "\n"
      "Open positions: " +
      IntegerToString(CountOurPositions()) + "\n"
      "Daily protection: " +
      (g_dailyBlocked ? "ACTIVE" : "OK") + "\n"
      "Drawdown protection: " +
      (g_drawdownBlocked ? "ACTIVE" : "OK") + "\n"
      "\n"
      "Risk: " +
      DoubleToString(InpRiskPercent,2) + "%\n"
      "========================================";

   Comment(text);
}

//====================================================================
// MANUAL START / STOP FUNCTIONS
//====================================================================

// These functions are available for future button integration.

void StartBot()
{
   g_running = true;
   g_status = "STARTED";
   Print("Axiom Style Gold AI STARTED.");
}

void StopBot()
{
   g_running = false;
   g_status = "STOPPED";
   Print("Axiom Style Gold AI STOPPED.");
}

//====================================================================
// EMERGENCY CLOSE
//====================================================================

void EmergencyCloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol ||
         magic != InpMagicNumber)
         continue;

      trade.PositionClose(ticket);
   }

   Print("Emergency close requested.");
}

//====================================================================
// TRADE TRANSACTION LOG
//====================================================================

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;

   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   string symbol =
      HistoryDealGetString(dealTicket,
                           DEAL_SYMBOL);

   long magic =
      HistoryDealGetInteger(dealTicket,
                            DEAL_MAGIC);

   if(symbol != _Symbol ||
      magic != InpMagicNumber)
      return;

   long entry =
      HistoryDealGetInteger(dealTicket,
                            DEAL_ENTRY);

   double profit =
      HistoryDealGetDouble(dealTicket,
                           DEAL_PROFIT);

   if(entry == DEAL_ENTRY_IN)
   {
      Print("[AXIOM] New position opened. Profit = ",
            DoubleToString(profit,2));
   }

   if(entry == DEAL_ENTRY_OUT)
   {
      Print("[AXIOM] Position closed. Result = ",
            DoubleToString(profit,2));
   }
}

//====================================================================
// END OF EA
//====================================================================
