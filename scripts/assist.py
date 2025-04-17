#!/usr/bin/env python3
"""
Assist with coding questions using the ingested Apple API Reference docset.

Usage:
  pip install -r requirements.txt
  python scripts/assist.py \
    --index data/docset_index.faiss \
    --meta data/docset_index.faiss.meta.json \
    --question "How do I create a UIView?" \
    [--openai_api_key YOUR_KEY] \
    [--topk 5] \
    [--embed_model text-embedding-ada-002] \
    [--chat_model gpt-4]
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
    import numpy as np
except ImportError:
    print("Missing dependency: numpy", file=sys.stderr)
    sys.exit(1)

def load_index(path):
    if not os.path.isfile(path):
        print(f"Index file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return faiss.read_index(path)

def load_metadata(path):
    if not os.path.isfile(path):
        print(f"Metadata file not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, 'r') as f:
        return json.load(f)

def embed_text(text, model):
    resp = openai.Embedding.create(input=[text], model=model)
    return resp['data'][0]['embedding']

def retrieve_docs(index, meta, query, embed_model, topk):
    emb = embed_text(query, embed_model)
    vec = np.array([emb], dtype='float32')
    D, I = index.search(vec, topk)
    results = []
    for dist, idx in zip(D[0], I[0]):
        entry = meta[idx]
        text = entry.get('text', '')
        name = entry.get('name', '<unknown>')
        results.append({'name': name, 'chunk': text, 'distance': float(dist)})
    return results



def main():
    parser = argparse.ArgumentParser(description='Retrieve relevant API docs from a docset index')
    parser.add_argument('--index', required=True, help='FAISS index file')
    parser.add_argument('--meta', required=True, help='Metadata JSON file for index')
    parser.add_argument('--question', required=True, help='Your coding question')
    parser.add_argument('--openai_api_key', default=None, help='OpenAI API key')
    parser.add_argument('--embed_model', default='text-embedding-ada-002', help='Embedding model')
    parser.add_argument('--topk', type=int, default=5, help='Number of snippets to retrieve')
    args = parser.parse_args()

    key = args.openai_api_key or os.getenv('OPENAI_API_KEY')
    if not key:
        print('Missing OpenAI API key', file=sys.stderr)
        sys.exit(1)
    openai.api_key = key

    index = load_index(args.index)
    meta = load_metadata(args.meta)

    # Retrieve top matching documentation snippets
    docs = retrieve_docs(index, meta, args.question, args.embed_model, args.topk)
    # Output snippets for manual or agent-assisted answering
    print(f"Top {len(docs)} documentation snippets for question: '{args.question}'\n")
    for i, doc in enumerate(docs, start=1):
        print(f"--- Snippet {i} ---")
        print(f"Doc: {doc['name']} (distance: {doc['distance']:.4f})")
        print(doc['chunk'])
        print()

if __name__ == '__main__':
    main()