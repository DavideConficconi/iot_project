module MessageTaskC
{
	provides interface MessageTask;
}
implementation
{

	async error_t command MessageTask.postTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload)
	{
		//printf("dst:%u msg:%u qos::%u nodeID:%u topic:%u payload:%u \n",dst, msg_type,qos,nodeID,topic,payload);
		signal MessageTask.runTask(dst, msg_type, qos, nodeID, topic, payload);
		return SUCCESS;
	}

}
