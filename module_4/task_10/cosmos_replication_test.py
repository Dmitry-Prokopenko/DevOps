import argparse
import random
import string
import time
from azure.cosmos import CosmosClient

# Function to generate random strings
def random_string(length=8):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Function to generate random item data
def generate_random_item():
    item_id = random_string(10)  # Random 10-character ID
    item_name = random_string(6)  # Random 6-character name
    category = random.choice(['Electronics', 'Clothing', 'Home', 'Toys', 'Books'])  # Random category
    price = random.randint(100, 1000)  # Random price between 100 and 1000
    return {
        'id': item_id,
        'name': item_name,
        'category': category,
        'price': price
    }

# Function to parse command-line arguments
def parse_arguments():
    parser = argparse.ArgumentParser(description="Test Cosmos DB replication and consistency.")
    parser.add_argument('--endpoint', type=str, required=True, help="Cosmos DB account endpoint.")
    parser.add_argument('--key', type=str, required=True, help="Cosmos DB account key.")
    parser.add_argument('--database_name', type=str, required=True, help="Name of the Cosmos DB database.")
    parser.add_argument('--container_name', type=str, required=True, help="Name of the Cosmos DB container.")
    parser.add_argument('--secondary_region', type=str, required=True, help="Secondary region for replication (e.g., 'canadaeast').")
    parser.add_argument('--consistency_level', type=str, default="Eventual", choices=["Eventual", "Session", "Strong"], help="Consistency level (default: 'Eventual').")
    parser.add_argument('--replication_delay', type=int, default=5, help="Time to wait for replication to complete (in seconds).")

    return parser.parse_args()

# Insert random data into Cosmos DB
def insert_random_data(container):
    item = generate_random_item()
    container.upsert_item(item)  # Insert or replace the item
    print(f"Inserted random item: {item}\n")
    return item['id']  # Return the id for querying later

# Query the inserted data from a region
def query_data(region_client, item_id):
    query = f"SELECT * FROM c WHERE c.id = '{item_id}'"
    items = list(region_client.query_items(query=query, enable_cross_partition_query=True))
    if len(items) > 0:
        print(f"Query returned from region: {items[0]}")
        return items[0]
    else:
        print("No items found.")
        return None

# Main function to execute the steps
def main():
    # Parse arguments
    args = parse_arguments()
    
    # Initialize Cosmos client
    client = CosmosClient(args.endpoint, args.key)

    # Get database and container references
    database = client.get_database_client(args.database_name)
    container = database.get_container_client(args.container_name)

    # Step 1: Insert random data
    print("Inserting random data into Cosmos DB...\n")
    item_id = insert_random_data(container)
    
    # Step 2: Wait for some time to allow replication (adjust as needed)
    print(f"Waiting for {args.replication_delay} seconds for replication to complete across regions...\n")
    time.sleep(args.replication_delay)  # Wait for the specified replication delay

    # Step 3: Query the data from the primary region to verify data exists
    print("Querying the inserted data from the primary region...\n")
    item_in_primary = query_data(container, item_id)
    
    if item_in_primary:
        print(f"Data consistency verified in primary region: {item_in_primary['name']} - {item_in_primary['category']} - {item_in_primary['price']}\n")
    else:
        print("Consistency test failed in primary region.\n")

    # Step 4: Create a CosmosClient with the secondary region
    # Initialize CosmosClient with the secondary region preference
    secondary_region_client = CosmosClient(
        args.endpoint,
        args.key,
        consistency_level=args.consistency_level,
        preferred_locations=[args.secondary_region]
    )
    
    secondary_database = secondary_region_client.get_database_client(args.database_name)
    secondary_container = secondary_database.get_container_client(args.container_name)

    # Step 5: Query the data from the secondary region to verify consistency
    print("Querying the inserted data from the secondary region...\n")
    item_in_secondary = query_data(secondary_container, item_id)

    if item_in_secondary:
        print(f"Data consistency verified in secondary region: {item_in_secondary['name']} - {item_in_secondary['category']} - {item_in_secondary['price']}")
    else:
        print("Consistency test failed in secondary region.")

if __name__ == '__main__':
    main()
