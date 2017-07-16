interface MessageTask {
  async error_t command postTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload);
  event void runTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload);
}