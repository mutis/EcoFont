#include <LiquidCrystal.h>
#include <EEPROM.h>
#include <Btn.h>

#define WATER_LEVEL_IN 0
#define RELAY_PIN 7
#define LED_BACKLIGHT 13
#define BTN_PIN 8
#define BTN2_PIN 6

#define WORK_MODE_MANUAL 0
#define WORK_MODE_AUTOMATIC 1

#define LCD_REFRESH 100 //ms
#define LCD_LIGHT 25 //s
#define PRESSURE 500 // Cada quan es mesura la pressió (ms)
#define LCD_REARMAR_DISPLAY 450 //ms
#define LCD_REARMAR_DISPLAY_PERIODIC 60000 //1 min
#define LCD_MESSAGE 5000 // 5 segons per a mostrar missatge
#define DISPLAY_PRESSIO 0
#define DISPLAY_VOLUM 1
#define DISPLAY_PUMP_ACTIVATED 2 // Temps de bombeig en segons
#define DISPLAY_PUMP_GAP 3 // Temps entre regs en minuts
#define DISPLAY_PUMP_GAP_LEFT 4 // Temps per al proper reg
#define DISPLAY_RESUM 5 // Mostrem un resum de paràmetres
#define DISPLAY_NO_ACTIU 6 // Sempre ha de ser l'últim. Per a simplificar codi.
#define DISPLAY_PUMP_ON 10 // Bomba funcionant
#define DISPLAY_MESSAGE 11 // Missatges

#define EEPROM_START_ADDR 0
#define EEPROM_CHECK_BYTE 111

#define WATER_TANK_HEIGHT 900 //mm

// Connections:
// rs (LCD pin 4) to Arduino pin 12
// rw (LCD pin 5) to Arduino pin 11
// enable (LCD pin 6) to Arduino pin 10
// LCD pin 15 to Arduino pin 13
// LCD pins d4, d5, d6, d7 to Arduino pins 5, 4, 3, 2
LiquidCrystal lcd(12, 11, 10, 5, 4, 3, 2);

Btn m_Btn(BTN_PIN);
Btn m_Btn2(BTN2_PIN);

int m_WorkMode = WORK_MODE_AUTOMATIC;

int m_sensorValue = 0;
int m_sensorValueVolum = 0;

int m_llum = LOW;

int m_PumpGap = 720; //minutes (cada 12h - 720min)
//int m_PumpGap = 1; //minutes (cada 12h - 720min)
int m_PumpActivated = 40;  //seconds

int m_Display = DISPLAY_PUMP_GAP_LEFT;
int m_DisplayTemp = DISPLAY_PRESSIO;
long m_temps = 0;

//Timers
long m_TimerLCDLight = -1;
long m_TimerLCDRefresh = -1;
long m_TimerPumpGap = -1;
long m_TimerPumpGapOffset = 0;
long m_TimerPumpActivated = -1;
long m_TimerPressure = -1;
long m_TimerMessage = -1;
long m_TimerRearmarDisplay = -1;
long m_TimerRearmarDisplayPeriodic = -1;

String m_Message = "";

// ----------------------------------------------------------------------
// -------------------- EEPROM ------------------------------------------
// ----------------------------------------------------------------------

template <class T> int EEPROM_writeAnything(int ee, const T& value)
{
    const byte* p = (const byte*)(const void*)&value;
    int i;
    for (i = 0; i < sizeof(value); i++)
	  EEPROM.write(ee++, *p++);
    return i;
}

template <class T> int EEPROM_readAnything(int ee, T& value)
{
    byte* p = (byte*)(void*)&value;
    int i;
    for (i = 0; i < sizeof(value); i++)
	  *p++ = EEPROM.read(ee++);
    return i;
}

// ----------------------------------------------------------------------
// -------------------- SETUP -------------------------------------------
// ----------------------------------------------------------------------
void setup()
{
  pinMode(RELAY_PIN, OUTPUT);        // Pump OUT
  pinMode(LED_BACKLIGHT, OUTPUT);    // LCD Light
  digitalWrite(LED_BACKLIGHT, HIGH);
  
  lcd.begin(16,2); // columns, rows
  lcd.clear();
  lcd.setCursor(0,0); // column 0, row 0
  lcd.print("EcoFont v1.1");
  lcd.setCursor(0,1); // column 0, row 0
  
  //Inicialitzem valors EEPROM
  if(EEPROM.read(EEPROM_START_ADDR)==EEPROM_CHECK_BYTE)
  {    
    //Llegim configuració
    lcd.print("Reading EEPROM...");
    EEPROM_readAnything( EEPROM_START_ADDR+1, m_PumpGap); //saltem el primer byte de check d'eeprom
    EEPROM_readAnything( EEPROM_START_ADDR+3, m_PumpActivated); //int:2bytes 
  }
  else
  {
    //Guardem configuració
    lcd.print("EEPROM Init...");    
    EEPROM_writeAnything( EEPROM_START_ADDR, EEPROM_CHECK_BYTE);
    EEPROM_writeAnything( EEPROM_START_ADDR+1, m_PumpGap);
    EEPROM_writeAnything( EEPROM_START_ADDR+3, m_PumpActivated);
  }
  
  delay(3000);
    
  m_TimerLCDRefresh = millis();  // Iniciem Timer LCD Refresh
  m_TimerPressure = millis(); // Comencem a monitoritzar la pressió
  m_TimerLCDLight = millis(); // Engeguem el llum
  m_TimerRearmarDisplayPeriodic = millis(); //Pool que va rearmant el display (per si es penja)
  
  SetWorkMode(WORK_MODE_AUTOMATIC);
}

// ----------------------------------------------------------------------
// -------------------- LOOP --------------------------------------------
// ----------------------------------------------------------------------
void loop()
{  
  //Timers
  GestTimerLlum();
  GestTimerLCDRefresh();
  GestTimerPressure();
  GestTimerPumpGap();
  GestTimerPumpActivated();
  GestTimerRearmarDisplay();
  GestTimerMessage();
  
  //Interface - 1 Button
  GestButton();
}

void SetWorkMode(int workMode)
{
  m_WorkMode = workMode;
  switch (m_WorkMode)
  {
    case WORK_MODE_AUTOMATIC:
      m_TimerPumpGapOffset = 0;
      m_TimerPumpActivated = -1;
      m_TimerPumpGap = millis();
      break;
    case WORK_MODE_MANUAL:
      m_TimerPumpGapOffset = 0;
      m_TimerPumpGap = -1;
      m_TimerPumpActivated = -1;
      break;
  }
}

void ActualitzaLCD( )
{ 
  long segons;
  
  if (m_Display == DISPLAY_NO_ACTIU)
    return;
  
  if (m_Display == DISPLAY_PUMP_ON)
    lcd.begin(16,2); // protegim per interferències durant el bombeig

  if (m_Display!=DISPLAY_RESUM&&m_Display!=DISPLAY_PUMP_ON)
  {
    lcd.setCursor(0,0);
    lcd.print("          ");
  }
  
  lcd.setCursor(10,0);
  switch (m_WorkMode)
  {
    case WORK_MODE_MANUAL:
      lcd.print(" [MAN]");
      break;      
    case WORK_MODE_AUTOMATIC:
      lcd.print("[AUTO]");
      break;
   }
   
  lcd.setCursor(0,1); // set cursor to column 0, row 1
  switch (m_Display)
  {
    case DISPLAY_PRESSIO:
      lcd.print("Pressio: "); 
      lcd.print(m_sensorValue); 
      break;      
    case DISPLAY_VOLUM:
      lcd.print("Aigua: "); 
      lcd.print(m_sensorValueVolum);
      lcd.print("mm");
      break;
    case DISPLAY_PUMP_ACTIVATED:
      lcd.print("Pump time: "); 
      lcd.print(m_PumpActivated);
      lcd.print("s");
      break;
    case DISPLAY_PUMP_GAP:
      lcd.print("Gap: ");
      if (m_PumpGap>60)
      {
        lcd.print(m_PumpGap);
        lcd.print("m (");
        lcd.print(m_PumpGap/60);
        lcd.print("h) ");
      }
      else
      {
        lcd.print(m_PumpGap);
        lcd.print("min");
      }
      break;
    case DISPLAY_PUMP_GAP_LEFT:
      lcd.print("Next: "); 
      if ( m_TimerPumpGap >= 0 )
      {
        segons = (((m_PumpGap*60000)-m_TimerPumpGapOffset)-(millis()-m_TimerPumpGap))/1000;
        if (segons>60)
        {
          if (segons>3600)
          {
            lcd.print(segons/60);
            lcd.print("m (");
            lcd.print(segons/3600);
            lcd.print("h) ");            
          }
          else
          {
            lcd.print(segons/60);
            lcd.print("m ");
          }
        }
        else
        {
          lcd.print(segons);
          lcd.print("s ");
        }
      }
      else
        lcd.print("OFF ");
      break;
    case DISPLAY_RESUM:
      lcd.setCursor(0,0);
      lcd.print("P");
      lcd.print(m_sensorValue); 
      lcd.print(" ");
      lcd.print(m_sensorValueVolum); 
      lcd.print("mm");
      lcd.setCursor(0,1);
      lcd.print("Nxt:");
      if ( m_TimerPumpGap >= 0 )
      {
        segons = (((m_PumpGap*60000)-m_TimerPumpGapOffset)-(millis()-m_TimerPumpGap))/1000;
        if (segons>60)
        {
          if (segons>3600)
          {
            lcd.print(segons/3600);
            lcd.print("h ");
          }
          else
          {
            lcd.print(segons/60);
            lcd.print("m ");
          }
        }
        else
        {
          lcd.print(segons);
          lcd.print("s ");
        }
      }
      else
        lcd.print("OFF ");
      lcd.print("");
      lcd.print(m_PumpGap);
      lcd.print(",");
      lcd.print(m_PumpActivated);
      lcd.print("");
      break;
    case DISPLAY_PUMP_ON:
      lcd.setCursor(0,0);
      lcd.print("PUMP ON!  ");    
      //mostrem els segons restants al display
      lcd.setCursor(0,1); // set cursor to column 0, row 1
      lcd.print("ON: "); 
      lcd.print((long)m_PumpActivated-(m_temps-m_TimerPumpActivated)/1000); 
      lcd.print(" P:"); 
      lcd.print(m_sensorValue);
      lcd.print("    ");
      break;
    case DISPLAY_MESSAGE:
      lcd.setCursor(0,0);
      lcd.print("NO WATER! "); 
      break;
  }
  lcd.print("         ");
}

void GestTimerLlum( )
{
  if (m_TimerLCDLight<0) //Timer no actiu
    digitalWrite(LED_BACKLIGHT, LOW);
  else if (millis()-m_TimerLCDLight>=LCD_LIGHT*1000) // Timer finalitzat
  {
    digitalWrite(LED_BACKLIGHT, LOW);
    m_TimerLCDLight=-1;
  }
  else  //Timer actiu
    digitalWrite(LED_BACKLIGHT, HIGH);
}


void GestTimerLCDRefresh( )
{
  if (m_TimerLCDRefresh>=0&&(millis()-m_TimerLCDRefresh>=LCD_REFRESH)) // Timer finalitzat
  {
    m_TimerLCDRefresh=millis();
    ActualitzaLCD();
  }
}

void GestTimerPressure( )
{
  if (m_TimerPressure>=0&&(millis()-m_TimerPressure>=PRESSURE)) // Timer finalitzat
  {
    m_sensorValue = analogRead(WATER_LEVEL_IN);
    //int mm = (5/3)*((long)((long)((long)m_sensorValue*350)/1024)-50);  //1024/5=717/3.-5              (5/3)*((sensorvalue*500)/1024)-50)
    int mm = 10*(long)((long)(500*(long)m_sensorValue/1023)-48.1891)/6.03622;
    m_sensorValueVolum = mm; //milímetres d'aigua per sobre del sensor
    //m_sensorValueVolum = (2*m_sensorValue)-110;
    m_TimerPressure=millis();
  }
}

void GestTimerPumpGap()
{
  if (m_TimerPumpGap>=0&&(millis()-m_TimerPumpGap>=(m_PumpGap*60000-m_TimerPumpGapOffset))) // Timer finalitzat
  {
    m_TimerPumpGap = -1;
    m_TimerPumpGapOffset = 0;
    m_DisplayTemp = m_Display; // Guardem el paràmetre que es visualitzava, doncs al funcionar la bomba es mostra el pendent
    m_Display = DISPLAY_PUMP_ON; // Desactivem el pintat de paràmetres mentres es bomba
    m_TimerPumpActivated = millis(); // Engegem la bomba
    m_TimerLCDLight = millis(); //Activem el display
  }
}

void GestTimerPumpActivated()
{
  boolean pump = false;
  m_temps = millis();
  
  if (m_TimerPumpActivated<0) //Timer no actiu
    digitalWrite(RELAY_PIN, LOW);
  else if (m_temps-m_TimerPumpActivated>=((long)m_PumpActivated)*1000) // Timer finalitzat
  {
    digitalWrite(RELAY_PIN, LOW);
    m_TimerPumpActivated=-1;
    m_Display = m_DisplayTemp; // Tornem a visualitzar el paràmetre que es mostrava abans de començar a bombar
    if (m_WorkMode!=WORK_MODE_MANUAL)
      m_TimerPumpGap = millis(); // Activem el timer per al proper reg
    m_TimerRearmarDisplay = millis(); //Esperem i rearmem display per interferències bomba
  }
  else if ( m_sensorValueVolum > 30 ) //Timer actiu si hi ha prou aigua (3cm per sobre del sensor)
  {
    if (m_Display!=DISPLAY_PUMP_ON)
      m_DisplayTemp = m_Display;
    m_Display = DISPLAY_PUMP_ON;
    digitalWrite(RELAY_PIN, HIGH);
  }
  else
  {
    m_TimerPumpActivated=-1; //desactivem la bomba pq no hi ha aigua
    if (m_Display != DISPLAY_MESSAGE)
      m_DisplayTemp = m_Display;
    m_Message = "NO WATER!";
    m_Display = DISPLAY_MESSAGE;
    m_TimerMessage = millis();
  }
}

void GestTimerRearmarDisplay( )
{
  if (m_TimerRearmarDisplay>=0&&(millis()-m_TimerRearmarDisplay>=LCD_REARMAR_DISPLAY)) // Timer finalitzat
  {
    m_TimerRearmarDisplay=-1; //esperem a que algú el torni a activar
    lcd.begin(16,2); // per les interferències generades per la bomba
  }
  if (m_TimerRearmarDisplayPeriodic>=0&&(millis()-m_TimerRearmarDisplayPeriodic>=LCD_REARMAR_DISPLAY_PERIODIC)) // Timer finalitzat
  {
    lcd.begin(16,2); 
    m_TimerRearmarDisplayPeriodic = millis(); //rearmem timer
  }
}

void GestTimerMessage( )
{
  if (m_TimerMessage>=0&&(millis()-m_TimerMessage>=LCD_MESSAGE)) // Timer finalitzat
  {
    m_TimerMessage=-1;
    m_Display = m_DisplayTemp;
  }
}

//=================================================
// Button

void GestButton()
{
   int b = m_Btn.checkButton();
   if (b == 1) clickEvent(1);
   if (b == 2) doubleClickEvent(1);
   if (b == 3) holdEvent(1);
   if (b == 4) longHoldEvent(1);
   
   int b2 = m_Btn2.checkButton();
   if (b2 == 1) clickEvent(2);
   if (b2 == 2) doubleClickEvent(2);
   if (b2 == 3) holdEvent(2);
   if (b2 == 4) longHoldEvent(2);
}

void clickEvent(int btn) 
{
  m_TimerLCDLight = millis();
  if (btn==1)
  {
    if (m_TimerLCDLight<0) // Si el display no està il·luminat, l'il·luminem i no fem res més
    {
      lcd.begin(16,2); //per interferències de bomba
      m_TimerLCDLight = millis();
      return;
    }
    if (m_TimerPumpActivated<0) // Protecció mentres es bomba, sinó es canvia de paràmetre a visualitzar
    {
      m_Display ++;
      if (m_Display >= DISPLAY_NO_ACTIU) 
        m_Display = DISPLAY_PRESSIO;
    } 
  }
  else if ((btn==2)&&(m_WorkMode==WORK_MODE_AUTOMATIC))
    IncrementaValor();
}

void doubleClickEvent(int btn)
{
  m_TimerLCDLight = millis();
  if (btn==1)
  {
     if (m_WorkMode==WORK_MODE_MANUAL)
     {
       if (m_TimerPumpActivated<0)
       {
         if (m_Display != DISPLAY_MESSAGE)
           m_DisplayTemp = m_Display;
         m_TimerPumpActivated = millis(); // Engeguem manualment la bomba
       }
       else
       {
         m_TimerPumpActivated = -1; //Parem la bomba
         m_Display = m_DisplayTemp;
         m_TimerRearmarDisplay = millis(); //Esperem i rearmem display
       }
     }
     else if (m_WorkMode==WORK_MODE_AUTOMATIC)
     {
       if (m_TimerPumpActivated>=0)
       {
         m_TimerPumpActivated = -1;
         m_TimerPumpGap = millis();
         m_TimerPumpGapOffset = 0;
         m_Display = m_DisplayTemp;
         return;
       }
       IncrementaValor();
     }
  }

}

void IncrementaValor()
{
   switch (m_Display)
   {        
     case DISPLAY_PUMP_ACTIVATED:
       m_PumpActivated += 10;  //seconds
       if (m_PumpActivated > 150)
         m_PumpActivated = 10;
       EEPROM_writeAnything( EEPROM_START_ADDR+3, m_PumpActivated);
       break;
     case DISPLAY_PUMP_GAP:
       m_PumpGap += 120; //minutes
       if (m_PumpGap > 1440)
         m_PumpGap = 360; // 360 minuts : cada 6 hores
       EEPROM_writeAnything( EEPROM_START_ADDR+1, m_PumpGap);
       break;
     case DISPLAY_PUMP_GAP_LEFT:
       m_TimerPumpGapOffset += 3600000; //avancem el proper temps d'arrencada en 1h
       break;
   }
}

void holdEvent(int btn) 
{
  m_TimerLCDLight = millis();
  if (btn==1)
  {
    // Canvi de mode de treball
    switch (m_WorkMode)
    {
      case WORK_MODE_MANUAL:
        SetWorkMode(WORK_MODE_AUTOMATIC);
        break;
      case WORK_MODE_AUTOMATIC:
        SetWorkMode(WORK_MODE_MANUAL);
        break;
    }
  }
}

void longHoldEvent(int btn) 
{
  m_TimerLCDLight = millis();
}
