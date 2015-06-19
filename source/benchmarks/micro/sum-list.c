#include <stdlib.h>

/*
typedef struct Node_t {
  int val;
  int neg; 
  struct Node_t* next;
} Node;

void sumList(Node* lst) {
  Node* n;
  int i;
  for (i = 0; i < 500000000; ++i) {
    for (n = lst; n != 0; n = n->next) {
      if (n->neg)
        n->val = n->val - 1;
      else
        n->val = n->val + 1;
    }
  }
}

int main() {
  Node* list = 0;
  int i;

  for (i = 0; i < 10; ++i)
  {
    Node* newNode = malloc(sizeof(Node));
    newNode->val = i;
    newNode->next = list;
    newNode->neg = (i % 2);
    list = newNode;
  }

  sumList(list);
  return 0;
}
*/

typedef struct Node_t {
  int val;
  struct Node_t* next;
} Node;

void sumList(Node* lst) {
  Node* n;
  int i;
  for (i = 0; i < 500000000; ++i) {
    for (n = lst; n != 0; n = n->next) {
        if (n->val)
            n->val = n->val + 1;
        else
            n->val = 1;
    }
  }
}

int main() {
  Node* list = 0;
  int i;

  for (i = 0; i < 10; ++i)
  {
    Node* newNode = malloc(sizeof(Node));

    if (i % 2 == 0)
    {
        newNode->val.i = i;
        newNode->type = 0;
    }
    else
    {
        newNode->val.f = i + 0.5;
        newNode->type = 1;
    }

    newNode->next = list;
    list = newNode;
  }

  sumList(list);
  return 0;
}

