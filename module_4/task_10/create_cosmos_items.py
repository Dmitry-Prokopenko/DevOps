import argparse
import random
import string
from azure.cosmos import CosmosClient

# Function to generate random strings
def random_string(length=8):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Function to generate random item data
def generate_random_item(item_id=None):
    if not item_id:
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
    parser = argparse.ArgumentParser(description="Create items in Cosmos DB.")
    parser.add_argument('--endpoint', type=str, required=True, help="Cosmos DB account endpoint.")
    parser.add_argument('--key', type=str, required=True, help="Cosmos DB account key.")
    parser.add_argument('--database_name', type=str, required=True, help="Name of the Cosmos DB database.")
    parser.add_argument('--container_name', type=str, required=True, help="Name of the Cosmos DB container.")
    parser.add_argument('--num_items', type=int, default=5, help="Number of items to insert.")
    
    return parser.parse_args()

# Insert random data into Cosmos DB
def insert_random_data(container, num_items):
    inserted_items = []
    for _ in range(num_items):
        item = generate_random_item()  # Create a random item
        container.upsert_item(item)  # Insert or replace the item
        inserted_items.append(item)  # Store the inserted items for verification
        print(f"Inserted item: {item}")
    return inserted_items

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
    print(f"Inserting {args.num_items} random items into Cosmos DB...")
    inserted_items = insert_random_data(container, args.num_items)
    

if __name__ == '__main__':
    main()
