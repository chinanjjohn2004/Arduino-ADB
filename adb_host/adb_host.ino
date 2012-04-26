/* Arduino ADB Host
 * April 25, 2012 by Davis D. Remmel (Copyright 2012 Davis D. Remmel)
 * A program to simulate an Apple Desktop Bus host, so ADB peripherals may
 * be used with non-native hardware.
 * 
 * Usage:
 *   Wire a 4-pin mini-DIN connector to the Arduino. A pinout may be found on
 *   the "Apple Desktop Bus" Wikipedia page. Connect +5v to the Arduino's VCC,
 *   GND to the Arduino's GND, and the ADB wire to the Arduino's pin 2. Do not
 *   connect the PSW pin.
 * 
 *   The Arduino will listen via the serial port for commands. Commands are
 *   sent from the attached computer, to take some of the load off the Arduino.
 * 
 * Goals:
 *   v0.1 - Read from an ADB mouse and calculate position on a 640x480 virtual
 *          screen.
 *   v0.2 - Read from an Apple Extended Keyboard II
 * 
 *   v1.0 - Transform this program into a library for ADB communication
 * 
 * Current status: An Arduino cannot act as a fully-functional ADB host. The 1-kilobyte of SRAM
 *                 makes data buffering impossible for more than 1 snooped byte with an acceptable
 *                 resolution.
 */

/***** Declarations *****/
const uint8_t ADB_pin = 2;  // Connect the ADB line to the Arduino's pin 2

/***** Setup *****/
void setup() {
  
  // Initialize the serial port
  Serial.begin(115200);
  Serial.println("Serial communication activated");
  
  // Start the bus as an output
  setBusAsOutput();
  Serial.println("ADB is at +5V");
  
  // Do a global reset so all devices are in vanilla mode
  ADBglobalReset();
  Serial.println("Global reset initiated; devices have been set to defaults");
  
  // Final call
  Serial.println("Waiting for input");
}

/***** Main Loop *****/
void loop() {
  
  // Wait for a command from the computer (over the serial port)
  if (Serial.available() > 0) {
    int inByte = Serial.read();  // inByte is sent from the computer
    switch (inByte) {
      /*
         If 'a' is recieved, send the contents of mouse register 3 over the
         serial port.
         
         The default action should be to keep ADB_pin high.
      */
      case 'a':
        sendCommandByte(B00111111);  // Device responds with Register 3 data
        relayADB();                  // Sends Register 3 data over serial port
      default:
        setBusAsOutput();
        break;
    }
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
  delay(5);  // Take it easy, give the line a rest
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
  
  /* Send the bits over the ADB bus, ignoring the null terminator bit */
  // this test will send them over the serial port to verify the code works
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

void relayADB() {  // Relays the ADB over the serial port
  
  // Set the ADB_pin to an input
  setBusAsInput();
  
  // Relay all bus information over the serial line (for all 8 theoretical bytes)
  // Serial.print takes too much time, so we'll read into an array
  bool a[150];               // Where the return data is stored
  for (uint16_t i = 0; i < 150; i++) {
    a[i] = digitalRead(ADB_pin);  // Saves time if printed via serial later
    delayMicroseconds(20);  // Keep in mind, the above instructions take time to execute
  }
  for (uint16_t i = 0; i < 150; i++) {  // it might be quicker to print this later
    Serial.print(a[i]);
  }
  Serial.println("");  // convienience line for multiple tries
  
  setBusAsOutput();  // Put the bus back the way it was (as a HIGH output)
}
///////////////////////////////////////////////////////////////////////////////////////////////////

