import os
import sys

def delete_stripped(folder_path):
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith("_stripped.v") or file.endswith("_stripped.sv"):
                full_path = os.path.join(root, file)
                os.remove(full_path)
                print(f"Deleted: {full_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python delete_stripped_files.py <folder_path>")
        sys.exit(1)

    delete_stripped(sys.argv[1])
