void setup() {
  Serial.begin(115200);
}

void loop() {
  if (Serial.available() > 0) {

    // Processingから1 byte受信（符号あり8ビット整数）
    int receivedByte = Serial.read();

    // ===============================
    // ここで将来的にはビート検出処理を行う
    // ===============================

    int sendData = (int8_t)receivedByte * (int8_t)receivedByte / 127; //ここを完成させる

    Serial.write(sendData); //ここを完成させる
  }
}