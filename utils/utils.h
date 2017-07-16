
#ifndef UTILS_H
#define UTILS_H


typedef nx_struct my_msg_t {
	//nx_uint16_t header;
	nx_uint8_t msg_type;
	nx_uint8_t qos;
	nx_uint16_t nodeID;

	nx_uint8_t topic;
	nx_uint16_t payload;
} my_msg_t;

#define CONNECT 1
#define CONNACK 2 
#define PUBLISH 3
#define PUBACK 4
#define SUBSCRIBE 5 
#define SUBACK 6

#define AM_PAN_COORD_ADDR 9 //AM_BROADCAST_ADDR

#define TASKNUMBER 3

#define TEMPERATURE_ID 0
#define HUMIDITY_ID 1
#define LUMINOSITY_ID 2

// 7 - 6 - 5 - 4 - 3 - 2 - 1 -0 
// msg type 7 -4
// 3 - 2 qos

// 

//payload--> topic 15 - 8, data 7 -0 
enum{
AM_MY_MSG = 6,
};


#endif