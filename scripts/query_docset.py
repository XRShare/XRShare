#!/usr/bin/env python3
"""
Retrieve relevant chunks from a FAISS index built from an Apple .docset.

Usage:
  pip install -r requirements.txt
  python scripts/query_docset.py --index data/docset_index.faiss --meta data/docset_index.faiss.meta.json --query "How do I create a UIView?"
"""
import os
import sys
import json
import argparse

try:
    import faiss
except ImportError:
    print("Missing dependency: faiss-cpu", file=sys.stderr)
    sys.exit(1)
try:
    import openai
except ImportError:
    print("Missing dependency: openai", file=sys.stderr)
    sys.exit(1)
try:
    import tiktoken
except ImportError:
    print("Missing dependency: tiktoken", file=sys.stderr)
    sys.exit(1)
import numpy as np

def embed_query(query, model):
    resp = openai.Embedding.create(input=[query], model=model)
    return resp['data'][0]['embedding']

def load_index(index_path):
    if not os.path.isfile(index_path):
        print(f"Index file not found: {index_path}", file=sys.stderr)
        sys.exit(1)
    return faiss.read_index(index_path)

def load_metadata(meta_path):
    if not os.path.isfile(meta_path):
        print(f"Metadata file not found: {meta_path}", file=sys.stderr)
        sys.exit(1)
    with open(meta_path, 'r') as f:
        return json.load(f)

def main():
    parser = argparse.ArgumentParser(description='Query a .docset FAISS index')
    parser.add_argument('--index', required=True, help='Path to FAISS index file')
    parser.add_argument('--meta', required=True, help='Path to metadata JSON file')
    parser.add_argument('--query', required=True, help='Query string')
    parser.add_argument('--model', default='text-embedding-ada-002', help='Embedding model')
    parser.add_argument('--openai_api_key', default=None, help='OpenAI API key')
    parser.add_argument('--topk', type=int, default=5, help='Number of results to retrieve')
    args = parser.parse_args()

    # Configure API key
    key = args.openai_api_key or os.getenv('OPENAI_API_KEY')
    if not key:
        print('Missing OpenAI API key (set --openai_api_key or env OPENAI_API_KEY)', file=sys.stderr)
        sys.exit(1)
    openai.api_key = key

    # Load index and metadata
    index = load_index(args.index)
    meta = load_metadata(args.meta)

    # Embed query
    print(f"Embedding query: '{args.query}'")
    embedding = embed_query(args.query, args.model)
    vec = np.array([embedding], dtype='float32')

    # Search
    D, I = index.search(vec, args.topk)

    # Display results
    print(f"Top {args.topk} results:")
    for dist, idx in zip(D[0], I[0]):
        chunk = meta[idx]['text']
        name = meta[idx].get('name', '<unknown>')
        print('---')
        print(f"Doc: {name} (distance: {dist:.4f})")
        print(chunk)
        print()

if __name__ == '__main__':
    main()