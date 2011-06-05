#ifndef BTN_H
#define BTN_H

#include "WProgram.h"

class Btn
{
  public:
    Btn(int btnPin);
    int checkButton();
  private: 
	int m_btnPin;
    // Button timing variables
	int debounce;          // ms debounce period to prevent flickering when pressing or releasing the button
	int DCgap;            // max ms between clicks for a double click event
	int holdTime;        // ms hold period: how long to wait for press+hold event
	int longHoldTime;    // ms long hold period: how long to wait for press+hold event

	// Button variables
	bool buttonVal;   // value read from button
	bool buttonLast;  // buffered value of the button's previous state
	bool DCwaiting;  // whether we're waiting for a double click (down)
	bool DConUp;     // whether to register a double click on next release, or whether to wait and click
	bool singleOK;    // whether it's OK to do a single click
	long downTime;         // time the button was pressed down
	long upTime;           // time the button was released
	bool ignoreUp;   // whether to ignore the button release because the click+hold was triggered
	bool waitForUp;        // when held, whether to wait for the up event
	bool holdEventPast;    // whether or not the hold event happened already
	bool longHoldEventPast ;// whether or not the long hold event happened already
};

#endif