#!/usr/bin/env python3
"""
Ingest an Apple .docset for retrieval or fine-tuning.

Usage:
  pip install -r requirements.txt
  python scripts/ingest_docset.py --docset /path/to/Apple_API_Reference.docset --output data/docset_index.faiss
"""
import os
import sys
import sqlite3
import argparse
import json

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("Missing dependency: beautifulsoup4", file=sys.stderr)
    sys.exit(1)
try:
    import openai
except ImportError:
    print("Missing dependency: openai", file=sys.stderr)
    sys.exit(1)
try:
    import faiss
except ImportError:
    print("Missing dependency: faiss-cpu", file=sys.stderr)
    sys.exit(1)
try:
    import tiktoken
except ImportError:
    print("Missing dependency: tiktoken", file=sys.stderr)
    sys.exit(1)
from tqdm import tqdm

def get_documents(docset_path):
    # Locate the SQLite index and HTML documents
    idx_path = os.path.join(docset_path, 'Contents/Resources/docSet.dsidx')
    docs_dir = os.path.join(docset_path, 'Contents/Resources/Documents')
    if not os.path.isfile(idx_path) or not os.path.isdir(docs_dir):
        print(f"Invalid docset path: {docset_path}", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(idx_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name, path FROM searchIndex WHERE path NOT NULL;")
    entries = cursor.fetchall()
    conn.close()
    docs = []
    for name, relpath in entries:
        file_path = os.path.join(docs_dir, relpath)
        if os.path.isfile(file_path):
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                html = f.read()
            # Strip HTML tags
            soup = BeautifulSoup(html, 'html.parser')
            text = soup.get_text(separator=' ', strip=True)
            docs.append((name, text))
    return docs

def chunk_text(text, max_tokens=500, overlap=50):
    # Split text into chunks of approximately max_tokens
    enc = tiktoken.get_encoding('gpt2')
    tokens = enc.encode(text)
    chunks = []
    for i in range(0, len(tokens), max_tokens - overlap):
        chunk = tokens[i:i + max_tokens]
        chunks.append(enc.decode(chunk))
    return chunks

def embed_texts(texts, model='text-embedding-ada-002'):
    # Embed a list of texts via OpenAI
    resp = openai.Embedding.create(input=texts, model=model)
    return [data['embedding'] for data in resp['data']]

def main():
    parser = argparse.ArgumentParser(description='Index an Apple .docset')
    parser.add_argument('--docset', required=True, help='Path to .docset folder')
    parser.add_argument('--output', required=True, help='Output FAISS index file')
    parser.add_argument('--model', default='text-embedding-ada-002', help='Embedding model')
    parser.add_argument('--openai_api_key', default=None, help='OpenAI API key')
    args = parser.parse_args()
    # Configure API key
    key = args.openai_api_key or os.getenv('OPENAI_API_KEY')
    if not key:
        print('Missing OpenAI API key (set --openai_api_key or env OPENAI_API_KEY)', file=sys.stderr)
        sys.exit(1)
    openai.api_key = key

    # Load documents
    print('Loading documents from docset...')
    docs = get_documents(args.docset)
    if not docs:
        print('No documents found in docset.', file=sys.stderr)
        sys.exit(1)

    # Chunk and embed; save metadata including chunk text
    texts, meta = [], []
    for name, text in docs:
        for chunk in chunk_text(text):
            texts.append(chunk)
            meta.append({'name': name, 'text': chunk})

    print(f'Encoding {len(texts)} text chunks...')
    embeddings = []
    batch_size = 50
    for i in tqdm(range(0, len(texts), batch_size)):
        batch = texts[i:i + batch_size]
        embs = embed_texts(batch, model=args.model)
        embeddings.extend(embs)

    # Build FAISS index
    dim = len(embeddings[0])
    index = faiss.IndexFlatL2(dim)
    import numpy as np
    index.add(np.array(embeddings, dtype='float32'))
    # Save index
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    faiss.write_index(index, args.output)
    # Save metadata
    meta_file = args.output + '.meta.json'
    with open(meta_file, 'w') as f:
        json.dump(meta, f)
    print(f'Index written to {args.output}')
    print(f'Metadata written to {meta_file}')

if __name__ == '__main__':
    main()