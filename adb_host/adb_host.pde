/* Arduino ADB Host
 * April 25, 2012
 * Copyright (c) 2012 Davis D. Remmel. All rights reserved.
 * 
 * Use an Arduino to act as a passthrough for communications between modern computers
 * and old Apple Desktop Bus peripherals.
 * 
 * Usage:
 *   Wire a 4-pin mini-DIN connector to the Arduino. A pinout may be found on
 *   the "Apple Desktop Bus" Wikipedia page. Connect +5v to the Arduino's VCC,
 *   GND to the Arduino's GND, and the ADB wire to the Arduino's pin 2. Do not
 *   connect the PSW pin.
 * 
 *   The Arduino will listen via the serial port for a byte. This byte should be
 *   pre-formed on the controlling computer before it is sent, because the Arduino
 *   is a dumb device that does what it is commanded to do. When a byte is sent
 *   from the computer over the serial line, the Arduino translates it to the Apple
 *   Desktop Bus (ADB). Then, whatever the reply on the bus is from a peripheral,
 *   that reply is translated to the serial line so it may be read by the computer.
 *
 *   The Arduino, when finished booting, will send 0x21 over the serial line to signal
 *   that it's ready. Once the computer recognizes this, it may proceed to send a byte
 *   which will be translated by the Arduino to the ADB. A very short while later, the
 *   Arduino will reply with the peripheral's transmission: all eight bytes, even if
 *   some of the bytes have no content (they are equal to 0x00). The transmission of
 *   each byte is delayed by 2 milliseconds, so the computer has time to run a little
 *   bit of storing code before reading the next byte.
 * 
 * Goals:
 *   v0.1 - Read from an ADB mouse and calculate position on a 640x480 virtual
 *          screen.
 *   v0.2 - Read from an Apple Extended Keyboard II
 * 
 *   v1.0 - Transform this program into a library for ADB communication
 * 
 * Current status: actively developed
 *
 * Restrictions:
 *     - If you pass an invalid byte, you're gonna have a bad time.
 *     - Want to use any part of this source code? Please, email me first at
 *       davis@davisremmel.com
 *     - The use of any part of this source code for commercial purposes is STRICTLY
 *       PROHIBITED. If you'd like to use it personally, please email me.
 */

/***** Declarations *****/
const uint8_t ADB_pin = 2;  // Connect the ADB line to the Arduino's pin 2

uint8_t registerBitDuration[66];  // Data recieved from a peripheral's register.
boolean registerBit[64]; // Where the converted durations are stored.
uint8_t registerByte[8];    // registerBit[] is converted to bytes and stored here. Can be 1 or 0.


/***** Setup *****/
void setup() {
  
  // Initialize the serial port
  Serial.begin(115200);
  
  // Start the bus as an output
  setBusAsOutput();
  
  // Do a global reset so all devices are in vanilla mode
  ADBglobalReset();
  
  // Send "all systems: go" byte
  Serial.write(0x21);  // 0x2{1..4} is (ASCII) Device Control {1..4}
}

/***** Main Loop *****/
void loop() {
  // Wait for a command from the computer (over the serial port)
  if (Serial.available() > 0) {
    byte inByte = Serial.read();  // inByte is sent from the computer
    sendCommandByte(inByte);      // and sent over the ADB.
    relayADB();                   // Then, we listen on the computer for a response from the ADB.
  }
}


/************************************************************
 * Global ADB signals                                       *
 * (Apple Guide to the Macintosh Family Hardware, page 317) *
 ************************************************************//////////////////////////////////////

// Attention //
void ADBattention() {
  // Attention signal pulls ADB_pin low for 800us
  digitalWrite(ADB_pin, LOW);
  delayMicroseconds(800);
}

// Sync //
void ADBsync() {
  // Sync signal goes high for 65us
  digitalWrite(ADB_pin, HIGH);
  delayMicroseconds(65);
}

// Global Reset //
void ADBglobalReset() {
  // Initiate a global reset (ADB_pin goes low for 3ms and returns high)
  digitalWrite(ADB_pin, LOW);
  delay(3);
  digitalWrite(ADB_pin, HIGH);
  delay(5);  // Take it easy, give the line a rest. It woke up on the wrong side of the bed.
}
///////////////////////////////////////////////////////////////////////////////////////////////////


/*****************
 * Reusable bits *
 *****************/////////////////////////////////////////////////////////////////////////////////

void ADBstartstopBit() {
  // I'm assuming a start bit is identical to a stop bit, since there isn't
  // any specific timing included in the AGttMFH. Figure 8-13 (on page 313)
  // shows the start bit like the stop bit.
  digitalWrite(ADB_pin, LOW);
  delayMicroseconds(70);        // Stop bit low time is 70us long, not 65us
  digitalWrite(ADB_pin, HIGH);  // We keep the line high for "stop to start" time
}

void ADBtruePulse() {
  digitalWrite(ADB_pin, LOW);
  delayMicroseconds(35);
  digitalWrite(ADB_pin, HIGH);
  delayMicroseconds(65);
}

void ADBfalsePulse() {
  digitalWrite(ADB_pin, LOW);
  delayMicroseconds(65);
  digitalWrite(ADB_pin, HIGH);
  delayMicroseconds(35);
}
 //////////////////////////////////////////////////////////////////////////////////////////////////
 

/******************************
 * Set bus as input or output *
 ******************************////////////////////////////////////////////////////////////////////

void setBusAsOutput() {  // Set the ADB bus as an output (commanding peripherals)
  pinMode(ADB_pin, OUTPUT);
  digitalWrite(ADB_pin, HIGH);  // When the ADB pin is not being used, set it high
}

void setBusAsInput() {  // Set the ADB bus as an input (reading data from peripherals)
  pinMode(ADB_pin, INPUT);
  digitalWrite(ADB_pin, HIGH);  // Keep the bus held high
}
///////////////////////////////////////////////////////////////////////////////////////////////////


/******************************
 * Sending and recieving data *
 ******************************////////////////////////////////////////////////////////////////////
/* Commented out because the Arduino is now acting like a 'passthrough' to the ADB
// User-friendly version of sendCommandByte()
// ! WARNING - DON'T PASS INVALID ARGUMENTS INTO THIS FUNCTION!
void sendCommand(byte deviceAddr, byte command, byte reg) {
  // Make a temporary byte, and form it by bit-shifting the device address, command, and register
  byte tempByte = B00000000;                             // Ex.  tempByte = 00000000
  tempByte = deviceAddr;                                 //      tempByte = 00000011, deviceAddr = B0011
  tempByte <<= 2;  // Commands are 2 bits long           //      tempByte = 00001100
  tempByte += command;                                   //      tempByte = 00001111, command = B11
  tempByte <<= 2;  // Registers are 2 bits long          //      tempByte = 00111100
  tempByte += reg;                                       //      tempByte = 00111101, register = B01  
  
  // Pass the temporary byte into sendCommandByte()
  sendCommandByte(tempByte);
}*/

void sendCommandByte(byte byteToSend) {  // Sends a byte over the ADB bus. Location info is contained
                                         // within the byte. (See page 315 of AGttMFH)

  /* Deconstruct the word-byte into bits, and store in an array */
  boolean binaryBoolArray[8];        // Store our binary values here. The rightmost (lowest) bit is stored in [7].
  for (uint8_t i = 0, inverse = 7; i < 8; i++, inverse--) {  // Read in the bits
    binaryBoolArray[inverse] = bitRead(byteToSend, i);
  }
  
  // Every command starts with an Attention and Sync signal
  ADBattention();
  ADBsync();
  
  /* Send the command bits over the ADB bus */
  for (uint8_t i = 0; i < 8; i++) {
    if (binaryBoolArray[i]) {
      ADBtruePulse();
    }
    else {
      ADBfalsePulse();
    }
  }
  // Send a stop bit
  ADBstartstopBit();
}

void relayADB() {  // Relays ADB data from peripherals over the serial port
  
  /* Set the ADB_pin to an input */
  setBusAsInput();
  
  /* Read the ADB pulse durations from the peripheral into the registerBit[] array */
  // We'll convert the durations into bits during a time-insensitive moment, later on.
  for (uint8_t i = 0; i < 66; i++) {
    registerBitDuration[i] = pulseIn(ADB_pin, LOW, 120);
  }
  setBusAsOutput();  // Put the bus back the way it was found (as a HIGH output)
  // <-- Everything after this is time-insensitive --> //
  
  /* DEBUG */
  for (int i = 0; i < 66; i++) {
    Serial.print(registerBitDuration[i]);
  }
  Serial.println("");
/* DEBUG */
  
  /* Convert recorded durations to actual bits */
  // Shift registerBitDuration[] left to get rid of the start-bit
  for (uint8_t i = 0; i < 64; i++) {
    registerBitDuration[i] = registerBitDuration[i+1];  // Copy desired bits into the first 64 elements
  }
  
  // Convert durations to bits
  for (uint8_t i = 0; i < 64; i++) {  // See page 313, Figure 8-13 of AGttMFH
    if ((registerBitDuration[i] >= 30) && (registerBitDuration[i] <=40))  // 5us tolerance
      registerBit[i] = 1;
    else if ((registerBitDuration[i] >= 60) && (registerBitDuration[i] <=70))
      registerBit[i] = 0;
  }
  
  // Convert register bits into pure bytes
  for (uint8_t a = 0; a < 8; a++) {  // a is the byte number
    // Write the bits to a temporary byte by shifting the register bit array into it
    byte tempByte = B00000000;
    for (uint8_t bitCount = ((a+1)*8)-8; bitCount < ((a+1)*8); bitCount++) {  // Calculates array location based on current byte loop count
      tempByte += registerBit[bitCount];  // Ex. tempByte = 00000001
      tempByte <<= 1;                     //     tempByte = 00000010
                                          //          ..loops..
                                          //     tempByte = 00000010
                                          //     tempByte = 00000100 .. until byte fills (8 bit counts)
    }
    
    // Assign the temporary byte's value to the real byte
    registerByte[a] = tempByte;
  }
  
  /* Send the read bytes from a peripheral's register over the serial port */
  for (uint8_t i = 0; i < 8; i++) {
    Serial.print(registerByte[i], HEX);
    Serial.print(' ');
//    delay(5);  // Give the computer some time to catch up
  }
  Serial.println("");
}
///////////////////////////////////////////////////////////////////////////////////////////////////

