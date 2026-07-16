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
#import <libimobiledevice/house_arrest.h>
#import <sys/socket.h>
#include <netdb.h>

bool doesUdidExist(struct idevice_info **devices, int count, char input[256]);
void printDeviceInfos(struct idevice_info **devices, int count);
void print_plist(plist_t node);
bool init_lockdown_client(idevice_t device, lockdownd_client_t *client, char* label);
bool start_lockdown_service(idevice_t device, lockdownd_client_t client, lockdownd_service_descriptor_t *service);
bool create_afc_client(idevice_t device, lockdownd_service_descriptor_t service, lockdownd_client_t client, afc_client_t *afc_client);

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
            
        case PLIST_ARRAY: {
            uint32_t size = plist_array_get_size(info);
            NSLog(@"ARRAY (%u items)", size);
            for (uint32_t i = 0; i < size; i++) {
                plist_t item = plist_array_get_item(info, i);
                NSLog(@"  [%u]:", i);
                print_plist(item);
            }
            break;
        }
            
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

void print_bundle_ids(plist_t apps) {
    if (plist_get_node_type(apps) != PLIST_ARRAY) {
        NSLog(@"Result is not an array");
        return;
    }
    
    uint32_t count = plist_array_get_size(apps);
    NSLog(@"Found %d user applications:", count);
    
    for (uint32_t i = 0; i < count; i++) {
        plist_t app_dict = plist_array_get_item(apps, i);
        
        // Get the CFBundleIdentifier key from the dictionary
        plist_t bundle_id_node = plist_dict_get_item(app_dict, "CFBundleIdentifier");
        
        if (bundle_id_node && plist_get_node_type(bundle_id_node) == PLIST_STRING) {
            char *bundle_id = NULL;
            plist_get_string_val(bundle_id_node, &bundle_id);
            
            NSLog(@"%d. %s", i + 1, bundle_id);
            
            free(bundle_id); // Remember to free strings retrieved from plist
        }
    }
}

enum CLIChoise {
    READ_PLIST,
    READ_DIRECTORY,
    SEE_INSTALLED,
};

bool init_lockdown_client(idevice_t device, lockdownd_client_t *client, char* label) {
    // now we have a udid we can create the lockdown client
    if (lockdownd_client_new_with_handshake(device, client, label) != LOCKDOWN_E_SUCCESS) {
        NSLog(@"Could Not Create lockdownd_client_t");
        return false;
    }
    NSLog(@"Created Lockdown Client");
    return true;
}

bool start_lockdown_service(idevice_t device, lockdownd_client_t client, lockdownd_service_descriptor_t *service) {
    if (lockdownd_start_service(client, "com.apple.afc", service) != LOCKDOWN_E_SUCCESS) {
        NSLog(@"Could Not Start Service To com.apple.afc");
        return false;
    }
    return true;
}

bool create_afc_client(idevice_t device, lockdownd_service_descriptor_t service, lockdownd_client_t client, afc_client_t *afc_client) {
    if (afc_client_new(device, service, afc_client) != AFC_E_SUCCESS) {
        NSLog(@"Could Not Create Client For com.apple.afc");
        return false;
    }
    return true;
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
        
        
        int user_choice = -1;
        
        
        lockdownd_client_t client = NULL;
        lockdownd_service_descriptor_t service = NULL;
        afc_client_t afc_client = NULL;
        char* label = "MyAwesomeApp";
        int exit_status = EXIT_SUCCESS;

        while (true) {
            NSLog(@"Pick a Choice");
            NSLog(@"1. Read Plist");
            NSLog(@"2. Read Directory");
            NSLog(@"3. See Installed");
            NSLog(@"4. to exit.");
            if (scanf("%d", &user_choice) != 1) {
                NSLog(@"That's not an integer");
                
                int character;
                while ((character = getchar()) != '\n' && character != EOF) {
                }
                
                continue;
            }
            
            if (user_choice == 4) {
                break;
            }
            if (user_choice < 1 || user_choice > 4) {
                NSLog(@"Invalid choice");
                continue;
            }
            
            enum CLIChoise choice = user_choice - 1;
            switch (choice) {
                case READ_PLIST: {
                    // verify client exists
                    if (client == NULL) {
                        if (!init_lockdown_client(device, &client, label)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    // verify service exists
                    if (service == NULL) {
                        if (!start_lockdown_service(device, client, &service)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    // verify afc_client exists
                    if (afc_client == NULL) {
                        if (!create_afc_client(device, service, client, &afc_client)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    
                    plist_t info = NULL;
                    if (afc_get_device_info_plist(afc_client, &info) != AFC_E_SUCCESS) {
                        NSLog(@"Could Not Get Device Info.plist");
                        exit_status = EXIT_FAILURE;
                        goto cleanup;
                    }
                    print_plist(info);
                    plist_free(info);
                    break;
                }
                case READ_DIRECTORY: {
                    // verify client exists
                    if (client == NULL) {
                        if (!init_lockdown_client(device, &client, label)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    // verify service exists
                    if (service == NULL) {
                        if (!start_lockdown_service(device, client, &service)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    // verify afc_client exists
                    if (afc_client == NULL) {
                        if (!create_afc_client(device, service, client, &afc_client)) {
                            exit_status = EXIT_FAILURE;
                            goto cleanup;
                        }
                    }
                    char **directory_info = NULL;
                    
                    if (afc_read_directory(afc_client, "/", &directory_info) != AFC_E_SUCCESS) {
                        NSLog(@"Could Not Read Directory");
                        exit_status = EXIT_FAILURE;
                        goto cleanup;
                    }
                    int i = 0;
                    while (directory_info[i] != NULL) {
                        NSLog(@"%s", directory_info[i]);
                        i++;
                    }
                    afc_dictionary_free(directory_info);
                    break;
                }
                case SEE_INSTALLED: {
                    // clear memory
                    afc_client_free(afc_client);
                    afc_client = NULL;
                    
                    lockdownd_service_descriptor_free(service);
                    service = NULL;
                    
                    instproxy_client_t iproxy = NULL;
                    if (instproxy_client_start_service(device, &iproxy, "MyAwesomeApp") != INSTPROXY_E_SUCCESS) {
                        NSLog(@"Could Not Start Installation Proxy");
                        exit_status = EXIT_FAILURE;
                        goto cleanup;
                    }
                    NSLog(@"Started Installation Proxy");
                    
                    // Set options to only return "User" apps (App Store / Sideloaded)
                    plist_t client_opts = instproxy_client_options_new();
                    instproxy_client_options_add(client_opts, "ApplicationType", "User", NULL);
                    
                    plist_t apps = NULL;
                    if (instproxy_browse(iproxy, client_opts, &apps) != INSTPROXY_E_SUCCESS) {
                        NSLog(@"Could Not Retrieve Apps");
                        exit_status = EXIT_FAILURE;
                        goto cleanup;
                    }
                    NSLog(@"Successfully fetched app list!");
                    print_bundle_ids(apps);
                    plist_free(apps);
                    instproxy_client_options_free(client_opts);
                    instproxy_client_free(iproxy);
                    break;
                }
            }
            
            continue;
        }
        
    cleanup:
        if (afc_client != NULL) {
            afc_client_free(afc_client);
        }
        
        if (service != NULL) {
            lockdownd_service_descriptor_free(service);
        }
        
        if (client != NULL) {
            lockdownd_client_free(client);
        }
        
        if (device != NULL) {
            idevice_free(device);
        }
        return exit_status;
        
    }
    return EXIT_SUCCESS;
}
