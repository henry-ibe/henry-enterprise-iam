from dataclasses import dataclass
from typing import List

@dataclass
class User:
    username: str
    full_name: str
    email: str
    groups: List[str]
    department: str
    
    def is_in_group(self, group_name: str) -> bool:
        return group_name in self.groups
    
    def has_role(self, department: str) -> bool:
        from config import Config
        required_group = Config.DEPARTMENT_GROUPS.get(department)
        return required_group in self.groups if required_group else False
    
    def to_dict(self):
        return {'username': self.username, 'full_name': self.full_name, 
                'email': self.email, 'groups': self.groups, 'department': self.department}
    
    @staticmethod
    def from_dict(data):
        return User(username=data.get('username'), full_name=data.get('full_name'),
                   email=data.get('email'), groups=data.get('groups', []), 
                   department=data.get('department'))
