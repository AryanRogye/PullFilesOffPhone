//
//  main.m
//  PullFilesOffPhone
//
//  Created by Aryan Rogye on 7/16/26.
//

#import <Foundation/Foundation.h>
#import <libimobiledevice/libimobiledevice.h>
#import <libimobiledevice/lockdown.h>
#import <libimobiledevice/afc.h>
#import <libimobiledevice/installation_proxy.h>
#import <sys/socket.h>
#include <netdb.h>

bool doesUdidExist(struct idevice_info **devices, int count, char input[256]);
void printDeviceInfos(struct idevice_info **devices, int count);
void print_plist(plist_t node);

bool doesUdidExist(struct idevice_info **devices, int count, char input[256]) {
    // we verify the udid exists
    for (int i = 0; i < count; i++) {
        char* udid = devices[i]->udid;
        if (strcmp(udid, input) == 0) {
            return true;
        }
    }
    
    return false;
}

void printDeviceInfos(struct idevice_info **devices, int count) {
    NSLog(@"Found %d Devices", count);
    for (int i = 0; i < count; i++) {
        char* udid = devices[i]->udid;
        enum idevice_connection_type conn_type = devices[i]->conn_type;
        void* conn_data = devices[i]->conn_data;
        
        NSLog(@"Device udid: %s", udid);
        switch (conn_type) {
            case CONNECTION_USBMUXD:
                NSLog(@"Device Available Over USB");
                break;
            case CONNECTION_NETWORK:
                NSLog(@"Device Available Over Network");
                break;
        }
        
        if (conn_data != NULL) {
            struct sockaddr* saddr = (struct sockaddr*)(conn_data);
            
            char hostBuffer[NI_MAXHOST];
            char serviceBuffer[NI_MAXSERV];
            
            int result = getnameinfo(saddr, saddr->sa_len,
                                     hostBuffer, sizeof(hostBuffer),
                                     serviceBuffer, sizeof(serviceBuffer),
                                     NI_NUMERICHOST | NI_NUMERICSERV);
            
            if (result == 0) {
                NSLog(@"[Socket] Family: %d, Address: %s, Port: %s", saddr->sa_family, hostBuffer, serviceBuffer);
            } else {
                NSLog(@"[Socket] Failed to parse address. Family: %d", saddr->sa_family);
            }
        }
    }

}

void print_plist(plist_t info) {
    switch (plist_get_node_type(info)) {
        case PLIST_NONE:
            NSLog(@"PLIST_NONE");
            break;
            
        case PLIST_BOOLEAN: {
            uint8_t value = 0;
            plist_get_bool_val(info, &value);
            NSLog(@"BOOL: %@", value ? @"true" : @"false");
            break;
        }
            
        case PLIST_INT: {
            uint64_t value = 0;
            plist_get_uint_val(info, &value);
            NSLog(@"UINT: %llu", value);
            break;
        }
            
        case PLIST_REAL: {
            double value = 0;
            plist_get_real_val(info, &value);
            NSLog(@"REAL: %f", value);
            break;
        }
            
        case PLIST_STRING: {
            char *value = NULL;
            plist_get_string_val(info, &value);
            NSLog(@"STRING: %s", value);
            free(value);
            break;
        }
            
        case PLIST_ARRAY:
            NSLog(@"ARRAY");
            break;
            
        case PLIST_DICT: {
            char *xml = NULL;
            uint32_t length = 0;
            
            plist_to_xml(info, &xml, &length);
            
            NSLog(@"%s", xml);
            
            free(xml);
            break;
        }
            
        case PLIST_DATE: {
            int64_t sec = 0;
            plist_get_unix_date_val(info, &sec);
            NSLog(@"DATE: %lld", sec);
            break;
        }
            
        case PLIST_DATA: {
            char *data = NULL;
            uint64_t length = 0;
            plist_get_data_val(info, &data, &length);
            NSLog(@"DATA (%llu bytes)", length);
            free(data);
            break;
        }
            
        case PLIST_KEY: {
            char *key = NULL;
            plist_get_key_val(info, &key);
            NSLog(@"KEY: %s", key);
            free(key);
            break;
        }
            
        case PLIST_UID: {
            uint64_t uid = 0;
            plist_get_uid_val(info, &uid);
            NSLog(@"UID: %llu", uid);
            break;
        }
            
        case PLIST_NULL:
            NSLog(@"NULL");
            break;
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        // listing out the devices to pick from
        struct idevice_info **devices = NULL;
        int count = 0;
        
        idevice_error_t error = idevice_get_device_list_extended(&devices, &count);
        if (error != IDEVICE_E_SUCCESS) {
            NSLog(@"Could Not Get Device List: %s", idevice_strerror(error));
            return EXIT_FAILURE;
        }
        
        // print info about the devices
        printDeviceInfos(devices, count);
        
        // ask input on the udid
        char input[256];
        printf("Enter Device udid: ");
        scanf("%255s", input);
        NSLog(@"You entered: %s", input);
        
        // check if exists if it doesnt free and return early
        if (!doesUdidExist(devices, count, input)) {
            NSLog(@"udid: %s does not exist", input);
            idevice_device_list_extended_free(devices);
            return EXIT_FAILURE;
        }
        // free since we dont need anymore
        idevice_device_list_extended_free(devices);
        
        // create new idevice_t
        idevice_t device = NULL;
        if (idevice_new(&device, input) != IDEVICE_E_SUCCESS) {
            NSLog(@"Could Not Create idevice_t");
            return EXIT_FAILURE;
        }
        NSLog(@"Created Device");
        
        // create a lockdownd_client_t
        lockdownd_client_t client = NULL;
        char* label = "MyAwesomeApp";
        
        // now we have a udid we can create the lockdown client
        if (lockdownd_client_new_with_handshake(device, &client, label) != LOCKDOWN_E_SUCCESS) {
            NSLog(@"Could Not Create lockdownd_client_t");
            idevice_free(device);
            return EXIT_FAILURE;
        }
        NSLog(@"Created Lockdown Client");
        
        lockdownd_service_descriptor_t service = NULL;
        if (lockdownd_start_service(client, "com.apple.afc", &service) != LOCKDOWN_E_SUCCESS) {
            NSLog(@"Could Not Start Service To com.apple.afc");
            idevice_free(device);
            lockdownd_client_free(client);
            return EXIT_FAILURE;
        }
        NSLog(@"Started Service To com.apple.afc");
        
        afc_client_t afc_client = NULL;
        if (afc_client_new(device, service, &afc_client) != AFC_E_SUCCESS) {
            NSLog(@"Could Not Create Client For com.apple.afc");
            lockdownd_service_descriptor_free(service);
            lockdownd_client_free(client);
            idevice_free(device);
            return EXIT_FAILURE;
        }
        NSLog(@"Created Client For com.apple.afc");
        
        plist_t info = NULL;
        if (afc_get_device_info_plist(afc_client, &info) != AFC_E_SUCCESS) {
            NSLog(@"Could Not Get Device Info.plist");
            lockdownd_service_descriptor_free(service);
            afc_client_free(afc_client);
            lockdownd_client_free(client);
            idevice_free(device);
            return EXIT_FAILURE;
        }
        print_plist(info);
        
        char **directory_info = NULL;
        
        if (afc_read_directory(afc_client, "/Downloads", &directory_info) != AFC_E_SUCCESS) {
            NSLog(@"Could Not Read Directory");
            lockdownd_service_descriptor_free(service);
            afc_client_free(afc_client);
            lockdownd_client_free(client);
            idevice_free(device);
            plist_free(info);
            return EXIT_FAILURE;
        }
        int i = 0;
        while (directory_info[i] != NULL) {
            NSLog(@"%s", directory_info[i]);
            i++;
        }
        
        free(directory_info);
        lockdownd_service_descriptor_free(service);
        afc_client_free(afc_client);
        lockdownd_client_free(client);
        idevice_free(device);
        plist_free(info);
    }
    return EXIT_SUCCESS;
}
