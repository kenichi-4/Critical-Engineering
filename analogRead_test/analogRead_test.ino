void setup()
{
  // Serial.begin(57600);
  // Serial.begin(74880);
  Serial.begin(115200);
  // Serial.begin(230400);
  // Serial.begin(250000);
  // Serial.begin(500000);
  // Serial.begin(1000000);
  pinMode(A0, INPUT);
  analogReadResolution(14);
}

void loop()
{
  long t0, t;

  t0 = micros();
  for(int i=0; i<10000; i++) {
    analogRead(A0);
  }
  t = micros()-t0;  // calculate elapsed time

  Serial.print(" Time per sample: ");
  Serial.println((float)t/10000);
  Serial.print(" Frequency: ");
  Serial.println((float)10000*1000000/t);
  Serial.println();
  delay(2000);
}
