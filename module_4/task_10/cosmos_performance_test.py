import argparse
from azure.cosmos import CosmosClient, exceptions
import time

# Function to parse command-line arguments
def parse_args():
    parser = argparse.ArgumentParser(description="Cosmos DB Query Performance Test")
    parser.add_argument('--endpoint', required=True, help='Cosmos DB endpoint (e.g., https://<account-name>.documents.azure.com:443/)')
    parser.add_argument('--key', required=True, help='Cosmos DB primary key')
    parser.add_argument('--database_name', required=True, help='Cosmos DB database name')
    parser.add_argument('--container_name', required=True, help='Cosmos DB container name')
    return parser.parse_args()

# Function to execute the query loop
def run_query_loop(endpoint, key, database_name, container_name, query, iterations):
    # Initialize Cosmos DB client
    client = CosmosClient(endpoint, key)

    # Select the database and container
    database = client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    # Loop to execute query multiple times
    for i in range(iterations):
        try:
            print(f"Executing Query #{i+1}")
            
            # Execute query and iterate through results
            items = list(container.query_items(query, enable_cross_partition_query=True))
            
            # Optional: Print first result to confirm
            if len(items) > 0:
                print(f"Result from Query #{i+1}: {items[0]}")
            else:
                print(f"No results for Query #{i+1}")
            
            # Optional: Sleep to add delay between queries
            time.sleep(1)  # 1-second delay
            
        except exceptions.CosmosHttpResponseError as e:
            print(f"Error executing query #{i+1}: {e}")

# Main function to run the script
def main():
    # Parse arguments from command line
    args = parse_args()

    # Query to run in loop
    query = "SELECT * FROM c ORDER BY c.timestamp DESC OFFSET 0 LIMIT 100"

    # Number of iterations (queries to run)
    iterations = 100

    # Run the query loop
    run_query_loop(args.endpoint, args.key, args.database_name, args.container_name, query, iterations)

# Ensure the script runs only if it's the main program
if __name__ == '__main__':
    main()
