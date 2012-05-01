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
const uint8_t ADB_OUT = 2;  // Connect the ADB line to the Arduino's pin 2
const uint8_t ADB_IN  = 3;

const uint8_t BITBUFFERSIZE = 100;  // Minimum of 66 (to allow for 8 bytes of device data + 2 start/stop bits)
  // Declare variables
  uint8_t rawData[BITBUFFERSIZE] = {0};  // Data recieved from a peripheral's register.
  byte registerByte[8] = {0};    // ADB device data is converted to bytes and stored here (can send max 8 bytes)
 

/***** Setup *****/
void setup() {
  
  // Initialize the serial port
  Serial.begin(115200);
  
  // Input/Outputs
  pinMode(ADB_OUT, OUTPUT);
  pinMode(ADB_IN, INPUT);
  
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
  // Attention signal pulls ADB low for 800us
  digitalWrite(ADB_OUT, HIGH);
  delayMicroseconds(800);
}

// Sync //
void ADBsync() {
  // Sync signal goes high for 65us
  digitalWrite(ADB_OUT, LOW);
  delayMicroseconds(65);
}

// Global Reset //
void ADBglobalReset() {
  // Initiate a global reset (ADB_OUT goes low for 3ms and returns high)
  digitalWrite(ADB_OUT, HIGH);
  delay(3);
}
///////////////////////////////////////////////////////////////////////////////////////////////////


/*****************
 * Reusable bits *
 *****************/////////////////////////////////////////////////////////////////////////////////

void ADBstartstopBit() {
  // I'm assuming a start bit is identical to a stop bit, since there isn't
  // any specific timing included in the AGttMFH. Figure 8-13 (on page 313)
  // shows the start bit like the stop bit.
  digitalWrite(ADB_OUT, HIGH);
  delayMicroseconds(70);        // Stop bit low time is 70us long, not 65us
  digitalWrite(ADB_OUT, LOW);
}

void ADBtruePulse() {
  digitalWrite(ADB_OUT, HIGH);
  delayMicroseconds(35);
  digitalWrite(ADB_OUT, LOW);
  delayMicroseconds(65);
}

void ADBfalsePulse() {
  digitalWrite(ADB_OUT, HIGH);
  delayMicroseconds(65);
  digitalWrite(ADB_OUT, LOW);
  delayMicroseconds(35);
}
 //////////////////////////////////////////////////////////////////////////////////////////////////


/******************************
 * Sending and recieving data *
 ******************************////////////////////////////////////////////////////////////////////

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

                  ///////////////////////////////////////////

/*
 * WARNING! THERE'S A BIG-ASS BUG IN THIS FUNCTION!
 *
 * When the bits are read, there is a start bit at the beginning of the device's communication,
 * and a stop bit when transmission ends. THIS FUNCTION ASSUMES THE DEVICE TRANSMITS 8 BYTES.
 * Most of the time, however, it won't!
 *
 * So, this function needs to be re-worked to chop the start and end bits off the transmission,
 * NOT off bits 0 and 65!
 *
 */               ///////////////////////////////////////////

void relayADB() {  // Relays ADB data from peripherals over the serial port
  
  /* Read the ADB pulse durations from the peripheral into the registerBit[] array */
  // We'll convert the durations into bits during a time-insensitive moment, later on.
  for (uint8_t i = 0; i < BITBUFFERSIZE; i++) {
    rawData[i] = pulseIn(ADB_IN, LOW, 150);
    // Some of these pulses could be zero at the beginning or end, so they will need to be cleaned
    // before further processnig.
  }
  // <-- Everything after this is time-insensitive --> //

//------------------------------------------------>
// New algorithm idea:
//    1. Read the data into RAWDATA[]. (array names are ambiguous)
//    2. What if the first bits timeout, so they are set equal to zero?
//   2a. Convert the delay times recorded in RAWDATA[] to bit values. If ==35, =1. If ==65, =0.
//       If ==else, =0. 
  for (uint8_t i = 0; i < BITBUFFERSIZE; i++) {  // See page 313, Figure 8-13 of AGttMFH
    if ((rawData[i] >= 25) && (rawData[i] <=45))  // 10us tolerance
      rawData[i] = 1;
    else
      rawData[i] = 0;
  }
  


//    3. Count to RAWDATA[index] where the first non-zero value occurs. It will be equal to one,
//       because this is the start bit.
//           (Example: RAWDATA[3] == 1; STARTBITINDEX = 3;) (RAWDATA[] == {0, 0, 0, 1, .. };)
  uint8_t startBitIndex = 0;  // Location of the start bit in rawData[]
  while (0 == rawData[startBitIndex]) { // Count to the start bit location in rawData[]
    startBitIndex++;
  }

//    4. Count to RAWDATA[index] where the last non-zero value occurs (hint: count backwards).
//       It will be equal to one, because this is the end bit.
//           (Example: RAWDATA[20] == 1; ENDBITINDEX = 20;)
  uint8_t endBitIndex = BITBUFFERSIZE - 1;  // Location of the end bit in rawData[]
  while (0 == rawData[endBitIndex]) {  // Count to the end bit location in rawData[]
    endBitIndex--;
  }

//    5. Shift every value in RAWDATA[] STARTBITINDEX+1 places to the left, so RAWDATA[0] will be the
//       first valuable bit in the data packet (the +1 will chop off the start bit).
//           (Example: RAWDATA[i] = RAWDATA[i+STARTBITINDEX+1];)
  for (uint8_t i = 0; i < BITBUFFERSIZE; i++) {
    rawData[i] = rawData[i + startBitIndex+1];  // I hope this copies null characters when it reaches the end
  }

//    6. Adjust ENDBITINDEX by the amount we shifted left, because it now is too high.
//           (Example: ENDBITINDEX = ENDBITINDEX - (STARTBITINDEX + 1);)
  endBitIndex -= (startBitIndex + 1);

//    7. Now, RAWDATA[0] holds the first bit of viable data. The last bit of viable data is held
//       in RAWDATA[ENDBITINDEX-1].
//    8. Knowing this, initialize VIABLEDATA[ENDBITINDEX-1] so it can't hold anything BUT our viable
//       data.
  byte viableData[endBitIndex-1];

//    9. In a loop, copy RAWDATA[i] into VIABLEDATA[i], ENDBITINDEX amount of times.
//           (Example: for (int i=0; i < ENDBITINDEX; i++) { VIABLEDATA[i] = RAWDATA[i]; } )
  for (uint8_t i = 0; i < endBitIndex; i++)
    viableData[i] = rawData[i];

//   10. VIABLEDATA[] is now completely filled with meaty bits.
//   11. Find the number of bytes that are stored in VIABLEDATA[].
//           (Example: VIABLEBYTES = ENDBITINDEX / 8;)  // ENDBITINDEX is also VIABLEBYTES.length!
  uint8_t viableBytes = endBitIndex / 8;

//   12. Convert the bits stored in VIABLEDATA[] into bytes, and store those bytes in registerByte[CURRENTBYTE].
//           (Example:      for (int CURRENTBYTE = 0; CURRENTBYTE < VIABLEBYTES; CURRENTBYTE++) {
//                          byte TEMPBYTE = 0;
//                            for (int i = ((CURRENTBYTE+1)*8)-8; i < (CURRENTBYTE+1)*8; i++) {  // i = bit number depends on current byte
//                              TEMPBYTE += VIABLEDATA[i];
//                              TEMPBYTE <<= 1;
//                            }
//                          registerByte[CURRENTBYTE] = TEMPBYTE;
//                          }
//
//
  for (uint8_t currentByte = 0; currentByte < viableBytes; currentByte++) {
    byte tempByte = 0;
    for (uint8_t i = ((currentByte+1)*8)-8; i < (currentByte+1)*8; i++) {  // i is the current bit number
      tempByte += viableData[i];
      tempByte <<= 1;
    }
    registerByte[currentByte] = tempByte;  // Doesn't copy all eight possible bytes, only the ones which were
                                           // transmitted. This means that registerByte[x] will most likely
                                           // have a null value.
  }


//-----------------END NEW ALGORITHM--------------------->


//--------------------------------------------->
// ------ OLD ALGORITHM, DO NOT USE ----------->
// -------------------------------------------->
//
//  /* Convert recorded durations to actual bits */
//  // Shift registerBitDuration[] left to get rid of the start-bit
//  for (uint8_t i = 0; i < 64; i++) {
//    registerBitDuration[i] = registerBitDuration[i+1];  // Copy desired bits into the first 64 elements
//  }
//  
//  // Convert durations to bits
//  for (uint8_t i = 0; i < 64; i++) {  // See page 313, Figure 8-13 of AGttMFH
//    if ((registerBitDuration[i] >= 25) && (registerBitDuration[i] <=45))  // 5us tolerance
//      registerBit[i] = 1;
//    else if ((registerBitDuration[i] >= 55) && (registerBitDuration[i] <=75))
//      registerBit[i] = 0;
//  }
//  
//  // Convert register bits into pure bytes
//  for (uint8_t a = 0; a < 8; a++) {  // a is the byte number
//    // Write the bits to a temporary byte by shifting the register bit array into it
//    byte tempByte = B00000000;
//    for (uint8_t bitCount = ((a+1)*8)-8; bitCount < ((a+1)*8); bitCount++) {  // Calculates array location based on current byte loop count
//      tempByte += registerBit[bitCount];  // Ex. tempByte = 00000001
//      tempByte <<= 1;                     //     tempByte = 00000010
//                                          //          ..loops..
//                                          //     tempByte = 00000010
//                                          //     tempByte = 00000100 .. until byte fills (8 bit counts)
//    }
//    
//    // Assign the temporary byte's value to the real byte
//    registerByte[a] = tempByte;
//  }
//-----------------------END OLD ALGORITHM---------------------->
  
  /* Send the read bytes from a peripheral's register over the serial port */
  for (uint8_t i = 0; i < 8; i++) {
    Serial.print(registerByte[i], HEX);
    Serial.print('\t');
//    delay(5);  // Give the computer some time to catch up
  }
  Serial.println("");
}
///////////////////////////////////////////////////////////////////////////////////////////////////

