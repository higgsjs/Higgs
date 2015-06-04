#include <stdlib.h>

typedef struct Node_t {
  int val;
  int flag; 
  struct Node_t* next; 
} Node;

int sumList(Node* lst) {
  Node* n;
  int sum;
  int i;
  for (i = 0; i < 500000000; ++i) {
    sum = 0;
    for (n = lst; n != 0; n = n->next) {
      if (n->flag)
        sum += n->val * 10;
      else
        sum += n->val;
    }

    return sum;
}

int main() {
  Node* list = 0;
  int i;

  for (i = 0; i < 10; ++i)
  {
    Node* newNode = malloc(sizeof(Node));
    newNode->val = i;
    newNode->next = list;
    newNode->flag = (i % 2);
    list = newNode;
  }

  sumList(list);
  return 0;
}

