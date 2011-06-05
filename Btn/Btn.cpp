#include "Btn.h"

/* 4-Way Button:  Click, Double-Click, Press+Hold, and Press+Long-Hold Test Sketch By Jeff Saltzman Oct. 13, 2009

To keep a physical interface as simple as possible, this sketch demonstrates generating four output events from a single push-button.
1) Click:  rapid press and release
2) Double-Click:  two clicks in quick succession
3) Press and Hold:  holding the button down
4) Long Press and Hold:  holding the button for a long time 
*/

//=================================================
//  MULTI-CLICK:  One Button, Multiple Events

Btn::Btn(int btnPin)
{
	m_btnPin = btnPin;
	debounce = 20; 
	DCgap = 250; 
	holdTime = 3000;
	longHoldTime = 5000; 
	buttonVal = HIGH;
	buttonLast = HIGH;
	DCwaiting = false; 
	DConUp = false;
	singleOK = true;
	downTime = -1;
	upTime = -1; 
	ignoreUp = false;
	waitForUp = false; 
	holdEventPast = false;
	longHoldEventPast = false;
	
	pinMode(m_btnPin, INPUT);
    digitalWrite(m_btnPin, HIGH);
}

int Btn::checkButton() 
{    
   int event = 0;
   buttonVal = digitalRead(m_btnPin);
   // Button pressed down
   if (buttonVal == LOW && buttonLast == HIGH && (millis() - upTime) > debounce)
   {
       downTime = millis();
       ignoreUp = false;
       waitForUp = false;
       singleOK = true;
       holdEventPast = false;
       longHoldEventPast = false;
       if ((millis()-upTime) < DCgap && DConUp == false && DCwaiting == true)  DConUp = true;
       else  DConUp = false;
       DCwaiting = false;
   }
   // Button released
   else if (buttonVal == HIGH && buttonLast == LOW && (millis() - downTime) > debounce)
   {        
       if (not ignoreUp)
       {
           upTime = millis();
           if (DConUp == false) DCwaiting = true;
           else
           {
               event = 2;
               DConUp = false;
               DCwaiting = false;
               singleOK = false;
           }
       }
   }
   // Test for normal click event: DCgap expired
   if ( buttonVal == HIGH && (millis()-upTime) >= DCgap && DCwaiting == true && DConUp == false && singleOK == true && event != 2)
   {
       event = 1;
       DCwaiting = false;
   }
   // Test for hold
   if (buttonVal == LOW && (millis() - downTime) >= holdTime) {
       // Trigger "normal" hold
       if (not holdEventPast)
       {
           event = 3;
           waitForUp = true;
           ignoreUp = true;
           DConUp = false;
           DCwaiting = false;
           //downTime = millis();
           holdEventPast = true;
       }
       // Trigger "long" hold
       if ((millis() - downTime) >= longHoldTime)
       {
           if (not longHoldEventPast)
           {
               event = 4;
               longHoldEventPast = true;
           }
       }
   }
   buttonLast = buttonVal;
   return event;
}