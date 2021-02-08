interface Pool{
     
     command bool empty();
     command uint8_t size();
     command uint8_t maxSize();
     command pool_t* get();
     command error_t put(pool_t* newVal);

}