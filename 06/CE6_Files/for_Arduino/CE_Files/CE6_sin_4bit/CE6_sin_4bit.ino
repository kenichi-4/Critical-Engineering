void setup() {
  Serial.begin(115200);
}

void loop() {
  if (Serial.available() > 0) {

    // 1 byte受信
    int receivedByte = Serial.read();

    // 上位4 bit
    int sample1 = (receivedByte >> 4) & 0x0F; // ここを作成する
    // 下位4 bit
    int sample2 = receivedByte & 0x0F; // ここを作成する

    // signed 4 bitへ変換
    if (sample1 >= 8) {
      sample1 -= 16;
    }
    if (sample2 >= 8) {
      sample2 -= 16;
    }

    int8_t data1 = sample1 * sample1 / 9;
    int8_t data2 = sample2 * sample2 / 9;
    
    // ----------------------------------------
    // 今回はそのまま返送
    // ----------------------------------------
    int packed = ((data1 & 0x0F) << 4) | (data2 & 0x0F); // ここを作成する
    Serial.write(packed);
  }
}