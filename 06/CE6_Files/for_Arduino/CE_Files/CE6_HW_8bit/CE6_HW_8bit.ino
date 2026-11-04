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

    // 2乗せずにそのまま返送
    int8_t sendData = (int8_t)receivedByte;

    Serial.write((uint8_t)sendData);
  }
}
